//! Cross-language vector verification: the committed roundtrip.bin must
//! decode to the same records the Haxe and TypeScript suites verify, and
//! re-encoding must reproduce the committed bytes exactly.

use boring_codec::{BoundsEm, GlyphMetrics, VectorError, decode_vector, encode_vector};

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
