//! Cross-language vector verification for the f32 generated Rust tree
//! (feature spec 23): the committed roundtrip.bin must decode to the same
//! records the f64 lanes verify, and re-encoding must reproduce the
//! committed bytes exactly: every vector value is a dyadic binary32, so
//! the wire stays byte-identical across the precision switch.

use boring_codec_f32_gen::{
    BinaryReader, BoundsEm, GlyphMetrics, VectorCodec, VectorError, VectorSort,
};

const VECTOR_BYTES: &[u8] = include_bytes!("../vectors/roundtrip.bin");

fn expected_records() -> Vec<GlyphMetrics> {
    vec![
        GlyphMetrics {
            code_point: 65,
            advance_em: 0.5,
            bounds: BoundsEm {
                x_min: 0.03125,
                y_min: -0.21875,
                x_max: 0.46875,
                y_max: 0.03125,
            },
        },
        GlyphMetrics {
            code_point: 19969,
            advance_em: 1.0,
            bounds: BoundsEm {
                x_min: 0.03125,
                y_min: -0.875,
                x_max: 0.96875,
                y_max: 0.03125,
            },
        },
        GlyphMetrics {
            code_point: 65292,
            advance_em: 0.5,
            bounds: BoundsEm {
                x_min: 0.03125,
                y_min: -0.21875,
                x_max: 0.46875,
                y_max: 0.03125,
            },
        },
        GlyphMetrics {
            code_point: 65311,
            advance_em: 0.75,
            bounds: BoundsEm {
                x_min: 0.0625,
                y_min: -0.15625,
                x_max: 0.6875,
                y_max: 0.0625,
            },
        },
    ]
}

#[test]
fn decoded_binary_matches_expected_records() {
    assert_eq!(VectorCodec::decode(VECTOR_BYTES), Ok(expected_records()));
}

#[test]
fn reencoding_reproduces_the_committed_bytes() {
    let encoded = VectorCodec::encode(&expected_records());
    assert_eq!(encoded, Ok(VECTOR_BYTES.to_vec()));
}

#[test]
fn round_trip_preserves_every_record() {
    let encoded = VectorCodec::encode(&expected_records());
    let decoded = encoded.and_then(|bytes| VectorCodec::decode(&bytes));
    assert_eq!(decoded, Ok(expected_records()));
}

#[test]
fn u16_and_u32_round_trip_in_big_endian_order() {
    let mut bytes: Vec<u8> = Vec::new();
    bytes.extend_from_slice(&0x1234u16.to_be_bytes());
    bytes.extend_from_slice(&0x56789abc_u32.to_be_bytes());
    assert_eq!(bytes, vec![0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc]);
    let mut reader = BinaryReader::new(&bytes);
    assert_eq!(reader.read_u16(), Ok(0x1234));
    assert_eq!(reader.read_u32(), Ok(0x56789abc));
    assert_eq!(reader.remaining(), 0);
}

#[test]
fn bad_magic_is_rejected() {
    assert_eq!(
        VectorCodec::decode(b"XXXX\x00\x00\x00\x00"),
        Err(VectorError::BadMagic)
    );
}

#[test]
fn truncated_input_is_rejected() {
    assert_eq!(
        VectorCodec::decode(&VECTOR_BYTES[..20]),
        Err(VectorError::UnexpectedEof)
    );
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut padded = VECTOR_BYTES.to_vec();
    padded.push(0);
    assert_eq!(
        VectorCodec::decode(&padded),
        Err(VectorError::TrailingBytes { remaining: 1 })
    );
}

// The decodable count domain is [0, 2^31) per docs/specs/binary/01-wire-format.md.

#[test]
fn huge_count_is_rejected() {
    assert_eq!(
        VectorCodec::decode(b"BRG1\xff\xff\xff\xff"),
        Err(VectorError::CountOverflow)
    );
}

#[test]
fn boundary_count_is_rejected() {
    assert_eq!(
        VectorCodec::decode(b"BRG1\x80\x00\x00\x00"),
        Err(VectorError::CountOverflow)
    );
}

// Sort runtime identity per docs/specs/features/17-sorting.md: the corpus
// and oracle are inline constants shared verbatim with the Haxe and
// TypeScript sort tests.

const SHUFFLED_KEYS: [u32; 40] = [
    0x82a1, 0x78e2, 0x76ef, 0x6371, 0x4e00, 0x0020, 0x7ad5, 0x74fc, 0x694a, 0x6f23, 0x6d30, 0x8a6d,
    0x617e, 0x7ebb, 0x3105, 0x5ba5, 0x6b3d, 0x8687, 0x7116, 0x7cc8, 0xff01, 0x8494, 0x80ae, 0x59b2,
    0x4ff3, 0x4e00, 0x9fff, 0x57bf, 0xff01, 0x6564, 0x53d9, 0x5d98, 0x6757, 0x3105, 0x5f8b, 0x7309,
    0x55cc, 0x51e6, 0x4e00, 0x887a,
];

const SORTED_KEYS: [u32; 40] = [
    0x20, 0x3105, 0x3105, 0x4e00, 0x4e00, 0x4e00, 0x4ff3, 0x51e6, 0x53d9, 0x55cc, 0x57bf, 0x59b2,
    0x5ba5, 0x5d98, 0x5f8b, 0x617e, 0x6371, 0x6564, 0x6757, 0x694a, 0x6b3d, 0x6d30, 0x6f23, 0x7116,
    0x7309, 0x74fc, 0x76ef, 0x78e2, 0x7ad5, 0x7cc8, 0x7ebb, 0x80ae, 0x82a1, 0x8494, 0x8687, 0x887a,
    0x8a6d, 0x9fff, 0xff01, 0xff01,
];

fn sort_corpus_records() -> Vec<GlyphMetrics> {
    let mut records = Vec::with_capacity(SHUFFLED_KEYS.len());
    let mut index: u32 = 0;
    for key in SHUFFLED_KEYS.iter() {
        // advance_em marks the input position for the stability assertion.
        records.push(GlyphMetrics {
            code_point: *key,
            // f32 has no From<u32>; every index here is far below 2^24,
            // so the cast is exact.
            advance_em: index as f32,
            bounds: BoundsEm {
                x_min: 0.0,
                y_min: 0.0,
                x_max: 0.0,
                y_max: 0.0,
            },
        });
        index += 1;
    }
    records
}

#[test]
fn sort_by_code_point_matches_the_shared_oracle() {
    let mut records = sort_corpus_records();
    VectorSort::by_code_point(&mut records);
    let sorted_keys: Vec<u32> = records.iter().map(|record| record.code_point).collect();
    assert_eq!(sorted_keys, SORTED_KEYS.to_vec());
}

#[test]
fn sort_by_code_point_is_stable_on_equal_keys() {
    let mut records = sort_corpus_records();
    VectorSort::by_code_point(&mut records);
    // advance_em marks the input position; equal keys keep input order.
    for pair in records.windows(2) {
        let (left, right) = (pair[0], pair[1]);
        if left.code_point == right.code_point {
            assert!(left.advance_em < right.advance_em);
        }
    }
}
