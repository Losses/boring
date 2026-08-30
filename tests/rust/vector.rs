//! Cross-language vector verification: the committed roundtrip.bin must
//! decode to the same records the Haxe and TypeScript suites verify, and
//! re-encoding must reproduce the committed bytes exactly.

use boring_codec::{
    BoundsEm, FloatWidth, GlyphMetrics, VectorError, VectorReader, decode_vector, encode_vector,
    encode_vector_with_width, float_width_of_magic, vector_byte_length, vector_sort_by_code_point,
};

const VECTOR_BYTES: &[u8] = include_bytes!("../vectors/roundtrip.bin");
const VECTOR_BYTES_F32: &[u8] = include_bytes!("../vectors/roundtrip-f32.bin");
const VECTOR_BYTES_F16: &[u8] = include_bytes!("../vectors/roundtrip-f16.bin");

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
    assert_eq!(decode_vector(VECTOR_BYTES), Ok(expected_records()));
}

#[test]
fn reencoding_reproduces_the_committed_bytes() {
    let encoded = encode_vector(&expected_records());
    assert_eq!(encoded, Ok(VECTOR_BYTES.to_vec()));
}

#[test]
fn round_trip_preserves_every_record() {
    let encoded = encode_vector(&expected_records());
    let decoded = encoded.and_then(|bytes| decode_vector(&bytes));
    assert_eq!(decoded, Ok(expected_records()));
}

// Block float widths per binary spec 05: the committed f32 and f16 vectors
// carry the same records as the f64 vector, and re-encoding the source
// records reproduces their bytes.

#[test]
fn f32_block_decodes_and_reencodes_the_committed_bytes() {
    assert_eq!(decode_vector(VECTOR_BYTES_F32), Ok(expected_records()));
    let encoded = encode_vector_with_width(&expected_records(), FloatWidth::F32);
    assert_eq!(encoded, Ok(VECTOR_BYTES_F32.to_vec()));
}

#[test]
fn f16_block_decodes_and_reencodes_the_committed_bytes() {
    assert_eq!(decode_vector(VECTOR_BYTES_F16), Ok(expected_records()));
    let encoded = encode_vector_with_width(&expected_records(), FloatWidth::F16);
    assert_eq!(encoded, Ok(VECTOR_BYTES_F16.to_vec()));
}

#[test]
fn magic_and_width_map_to_each_other() {
    assert_eq!(FloatWidth::F64.magic(), b"BRG1");
    assert_eq!(FloatWidth::F32.magic(), b"BRG2");
    assert_eq!(FloatWidth::F16.magic(), b"BRG3");
    assert_eq!(float_width_of_magic(b"BRG1"), Some(FloatWidth::F64));
    assert_eq!(float_width_of_magic(b"BRG2"), Some(FloatWidth::F32));
    assert_eq!(float_width_of_magic(b"BRG3"), Some(FloatWidth::F16));
    assert_eq!(float_width_of_magic(b"BRG4"), None);
}

#[test]
fn block_byte_lengths_follow_the_width_marker() {
    assert_eq!(vector_byte_length(4, FloatWidth::F64), 184);
    assert_eq!(vector_byte_length(4, FloatWidth::F32), 104);
    assert_eq!(vector_byte_length(4, FloatWidth::F16), 64);
    assert_eq!(FloatWidth::F64.record_byte_length(), 44);
    assert_eq!(FloatWidth::F32.record_byte_length(), 24);
    assert_eq!(FloatWidth::F16.record_byte_length(), 14);
}

#[test]
fn unknown_width_magic_is_rejected() {
    // A future width magic must be rejected explicitly, never misread.
    assert_eq!(
        decode_vector(b"BRG4\x00\x00\x00\x00"),
        Err(VectorError::BadMagic)
    );
}

#[test]
fn u16_and_u32_round_trip_in_big_endian_order() {
    let mut bytes: Vec<u8> = Vec::new();
    bytes.extend_from_slice(&0x1234u16.to_be_bytes());
    bytes.extend_from_slice(&0x56789abc_u32.to_be_bytes());
    assert_eq!(bytes, vec![0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc]);
    let mut reader = VectorReader::new(&bytes);
    assert_eq!(reader.read_u16(), Ok(0x1234));
    assert_eq!(reader.read_u32(), Ok(0x56789abc));
    assert_eq!(reader.remaining(), 0);
}

#[test]
fn bad_magic_is_rejected() {
    assert_eq!(
        decode_vector(b"XXXX\x00\x00\x00\x00"),
        Err(VectorError::BadMagic)
    );
}

#[test]
fn truncated_input_is_rejected() {
    assert_eq!(
        decode_vector(&VECTOR_BYTES[..20]),
        Err(VectorError::UnexpectedEof)
    );
}

#[test]
fn trailing_bytes_are_rejected() {
    let mut padded = VECTOR_BYTES.to_vec();
    padded.push(0);
    assert_eq!(
        decode_vector(&padded),
        Err(VectorError::TrailingBytes { remaining: 1 })
    );
}

// The decodable count domain is [0, 2^31) per docs/specs/binary/01-wire-format.md.

#[test]
fn huge_count_is_rejected() {
    assert_eq!(
        decode_vector(b"BRG1\xff\xff\xff\xff"),
        Err(VectorError::CountOverflow)
    );
}

#[test]
fn boundary_count_is_rejected() {
    assert_eq!(
        decode_vector(b"BRG1\x80\x00\x00\x00"),
        Err(VectorError::CountOverflow)
    );
}

// Sort runtime identity per docs/specs/features/17-sorting.md: the input
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

fn sort_fixture_records() -> Vec<GlyphMetrics> {
    let mut records = Vec::with_capacity(SHUFFLED_KEYS.len());
    let mut index: u32 = 0;
    for key in SHUFFLED_KEYS.iter() {
        // advance_em marks the input position for the stability assertion.
        records.push(GlyphMetrics {
            code_point: *key,
            advance_em: f64::from(index),
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
    let mut records = sort_fixture_records();
    vector_sort_by_code_point(&mut records);
    let sorted_keys: Vec<u32> = records.iter().map(|record| record.code_point).collect();
    assert_eq!(sorted_keys, SORTED_KEYS.to_vec());
}

#[test]
fn sort_by_code_point_is_stable_on_equal_keys() {
    let mut records = sort_fixture_records();
    vector_sort_by_code_point(&mut records);
    // advance_em marks the input position; equal keys keep input order.
    for pair in records.windows(2) {
        let (left, right) = (pair[0], pair[1]);
        if left.code_point == right.code_point {
            assert!(left.advance_em < right.advance_em);
        }
    }
}
