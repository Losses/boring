//! Shared vector format codec for the boring repository: 4 magic bytes that
//! declare the block float width (binary spec 05), one u32 record count,
//! then one fixed-width record per glyph metric (u32 code point, five float
//! values at the block width), all big-endian. The Haxe, TypeScript, and
//! Kotlin suites read and write the same bytes.
//!
//! Conversion style: no integer `as` casts and no panicking conversions;
//! every fallible step returns a `VectorError`. The float-width `as` cast
//! at the binary32 wire edge is the format's declared round-to-nearest-even
//! conversion ruled by binary spec 05.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BoundsEm {
    pub x_min: f64,
    pub y_min: f64,
    pub x_max: f64,
    pub y_max: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}

pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";
pub const VECTOR_MAGIC_F32: &[u8; 4] = b"BRG2";
pub const VECTOR_MAGIC_F16: &[u8; 4] = b"BRG3";
pub const RECORD_BYTE_LENGTH: usize = 44;

/// Block float width of a vector block (binary spec 05). The width is a
/// property of the encoded bytes, declared by the magic, and stays
/// independent of the module real width that feature spec 23 selects at
/// compile time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FloatWidth {
    F64,
    F32,
    F16,
}

impl FloatWidth {
    pub fn magic(self) -> &'static [u8; 4] {
        match self {
            FloatWidth::F64 => VECTOR_MAGIC,
            FloatWidth::F32 => VECTOR_MAGIC_F32,
            FloatWidth::F16 => VECTOR_MAGIC_F16,
        }
    }

    pub fn record_byte_length(self) -> usize {
        match self {
            FloatWidth::F64 => 4 + 5 * 8,
            FloatWidth::F32 => 4 + 5 * 4,
            FloatWidth::F16 => 4 + 5 * 2,
        }
    }
}

/// Unknown magics answer None, which decode_vector reports as BadMagic; a
/// reader built before a width existed rejects the block explicitly instead
/// of misreading its records.
pub fn float_width_of_magic(magic: &[u8]) -> Option<FloatWidth> {
    if magic == VECTOR_MAGIC {
        Some(FloatWidth::F64)
    } else if magic == VECTOR_MAGIC_F32 {
        Some(FloatWidth::F32)
    } else if magic == VECTOR_MAGIC_F16 {
        Some(FloatWidth::F16)
    } else {
        None
    }
}

/// IEEE 754 binary16 conversions over plain integer arithmetic (binary
/// spec 05). Both directions operate on bit patterns so every tree computes
/// the same rounding. f32_to_f16_bits rounds with round-to-nearest-even,
/// flushes magnitude overflow to infinity, and quiets NaN inputs; it answers
/// the 16-bit pattern carried in the low half of a u32, which keeps every
/// internal step inside u32 arithmetic.
mod fp16 {
    pub fn f16_to_f32_bits(h16: u32) -> u32 {
        let sign = (h16 >> 15) & 1;
        let exp5 = (h16 >> 10) & 0x1f;
        let mant10 = h16 & 0x3ff;
        if exp5 == 0 {
            if mant10 == 0 {
                return sign << 31;
            }
            // A subnormal binary16 is mant10 * 2^-24; shifting the mantissa
            // into the implicit-bit position recovers the normal exponent.
            let mut mant = mant10;
            let mut shift: u32 = 0;
            while mant & 0x400 == 0 {
                mant <<= 1;
                shift += 1;
            }
            return (sign << 31) | ((113 - shift) << 23) | ((mant & 0x3ff) << 13);
        }
        if exp5 == 0x1f {
            if mant10 == 0 {
                return (sign << 31) | 0x7f80_0000;
            }
            return (sign << 31) | 0x7fc0_0000 | ((mant10 & 0x3ff) << 13);
        }
        // exp5 + 112 folds the -15 + 127 bias into one addition; the
        // folded form keeps every intermediate inside u32 for exp5 < 15.
        (sign << 31) | ((exp5 + 112) << 23) | (mant10 << 13)
    }

    pub fn f32_to_f16_bits(b32: u32) -> u32 {
        let sign = (b32 >> 31) << 15;
        let exp8 = (b32 >> 23) & 0xff;
        let mant23 = b32 & 0x7f_ffff;
        if exp8 == 0xff {
            if mant23 == 0 {
                return sign | 0x7c00;
            }
            return sign | 0x7e00 | (mant23 >> 13);
        }
        // Every binary32 subnormal lies far below half of the smallest
        // binary16 subnormal, so it rounds to a signed zero.
        if exp8 == 0 {
            return sign;
        }
        // The stored binary16 exponent is exp8 - 112; comparing exp8 against
        // the range boundaries first keeps every subtraction in range.
        if exp8 >= 143 {
            return sign | 0x7c00;
        }
        if exp8 >= 113 {
            let stored = exp8 - 112;
            let sig11 = round_shift(mant23 | 0x80_0000, 13);
            if sig11 == 0x800 {
                // A carry out of the significand increments the exponent and
                // resets the significand to its implicit-bit-only value; an
                // exponent that reaches 31 is infinity.
                if stored == 30 {
                    return sign | 0x7c00;
                }
                return sign | ((stored + 1) << 10);
            }
            return sign | (stored << 10) | (sig11 & 0x3ff);
        }
        // Subnormal binary16 target: the 24-bit significand shifts at least
        // 14 places, and more than 24 places rounds everything to a signed
        // zero.
        let shift = 126 - exp8;
        if shift > 24 {
            return sign;
        }
        let h = round_shift(mant23 | 0x80_0000, shift);
        // Rounding past the largest subnormal lands on the smallest normal
        // binary16, 2^-14, whose bit pattern is an exponent of one.
        if h == 0x400 {
            return sign | 0x0400;
        }
        sign | h
    }

    /// Shifts a 24-bit significand right and rounds to nearest with ties to
    /// even. shift stays within [13, 24] for every caller above.
    fn round_shift(value: u32, shift: u32) -> u32 {
        let base = value >> shift;
        let rest = value & ((1 << shift) - 1);
        let half = 1 << (shift - 1);
        if rest > half || (rest == half && (base & 1) == 1) {
            return base + 1;
        }
        base
    }
}

/// Rounds an f64 field to binary32 bits with round-to-nearest-even for
/// `WireF32Be` encoding (binary spec 05). The float-to-float `as` cast
/// rounds; the integer-cast ban of this file does not apply to it.
fn f64_to_f32_bits(value: f64) -> u32 {
    (value as f32).to_bits()
}

fn append_float(bytes: &mut Vec<u8>, value: f64, width: FloatWidth) {
    match width {
        FloatWidth::F64 => bytes.extend_from_slice(&value.to_bits().to_be_bytes()),
        FloatWidth::F32 => bytes.extend_from_slice(&f64_to_f32_bits(value).to_be_bytes()),
        FloatWidth::F16 => {
            let pattern = fp16::f32_to_f16_bits(f64_to_f32_bits(value));
            // The pattern occupies the low half of the u32, so its
            // big-endian bytes 2 and 3 are the two wire bytes.
            let full = pattern.to_be_bytes();
            bytes.extend_from_slice(&full[2..4]);
        }
    }
}

fn read_float(reader: &mut VectorReader<'_>, width: FloatWidth) -> Result<f64, VectorError> {
    match width {
        FloatWidth::F64 => reader.read_f64(),
        FloatWidth::F32 => reader.read_f32(),
        FloatWidth::F16 => reader.read_f16(),
    }
}

#[derive(Debug, PartialEq)]
pub enum VectorError {
    BadMagic,
    CountOverflow,
    UnexpectedEof,
    TrailingBytes { remaining: usize },
}

impl std::fmt::Display for VectorError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VectorError::BadMagic => write!(formatter, "bad vector magic"),
            VectorError::CountOverflow => write!(formatter, "record count exceeds u32"),
            VectorError::UnexpectedEof => write!(formatter, "vector ended mid-record"),
            VectorError::TrailingBytes { remaining } => {
                write!(formatter, "trailing bytes in vector: {remaining}")
            }
        }
    }
}

impl std::error::Error for VectorError {}

/// Cursor-based big-endian reader over an immutable byte slice.
pub struct VectorReader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> VectorReader<'a> {
    pub fn new(bytes: &'a [u8]) -> Self {
        VectorReader { bytes, offset: 0 }
    }

    pub fn read_u16(&mut self) -> Result<u16, VectorError> {
        Ok(u16::from_be_bytes(self.take_n::<2>()?))
    }

    pub fn read_u32(&mut self) -> Result<u32, VectorError> {
        Ok(u32::from_be_bytes(self.take_n::<4>()?))
    }

    pub fn read_f64(&mut self) -> Result<f64, VectorError> {
        Ok(f64::from_bits(u64::from_be_bytes(self.take_n::<8>()?)))
    }

    /// Reads a `WireF32Be` field and widens the binary32 value to the f64
    /// record field (binary spec 05); widening is exact.
    pub fn read_f32(&mut self) -> Result<f64, VectorError> {
        Ok(f64::from(f32::from_bits(self.read_u32()?)))
    }

    /// Reads a `WireF16Be` field, widens the binary16 value through
    /// binary32, and answers the f64 record field (binary spec 05).
    pub fn read_f16(&mut self) -> Result<f64, VectorError> {
        let h16 = u32::from(self.read_u16()?);
        Ok(f64::from(f32::from_bits(fp16::f16_to_f32_bits(h16))))
    }

    pub fn remaining(&self) -> usize {
        self.bytes.len() - self.offset
    }

    fn take_n<const N: usize>(&mut self) -> Result<[u8; N], VectorError> {
        match self.bytes[self.offset..].split_first_chunk::<N>() {
            Some((head, _)) => {
                self.offset += N;
                Ok(*head)
            }
            None => Err(VectorError::UnexpectedEof),
        }
    }
}

/// Encodes at the f64 block float width; encode_vector_with_width carries
/// the width parameter of binary spec 05.
pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    encode_vector_with_width(records, FloatWidth::F64)
}

pub fn encode_vector_with_width(
    records: &[GlyphMetrics],
    width: FloatWidth,
) -> Result<Vec<u8>, VectorError> {
    let count = u32::try_from(records.len()).map_err(|_| VectorError::CountOverflow)?;
    let mut bytes = Vec::with_capacity(8 + records.len() * width.record_byte_length());
    bytes.extend_from_slice(width.magic());
    bytes.extend_from_slice(&count.to_be_bytes());
    for record in records {
        bytes.extend_from_slice(&record.code_point.to_be_bytes());
        append_float(&mut bytes, record.advance_em, width);
        append_float(&mut bytes, record.bounds.x_min, width);
        append_float(&mut bytes, record.bounds.y_min, width);
        append_float(&mut bytes, record.bounds.x_max, width);
        append_float(&mut bytes, record.bounds.y_max, width);
    }
    Ok(bytes)
}

pub fn vector_byte_length(record_count: usize, width: FloatWidth) -> usize {
    8 + record_count * width.record_byte_length()
}

pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    if bytes.len() < 4 {
        return Err(VectorError::BadMagic);
    }
    let width = float_width_of_magic(&bytes[..4]).ok_or(VectorError::BadMagic)?;
    let mut reader = VectorReader::new(&bytes[4..]);
    let count = reader.read_u32()?;
    // The decodable count domain is [0, 2^31): counts at or above the signed
    // 32-bit boundary are rejected before any allocation or record read.
    if count > 2147483647 {
        return Err(VectorError::CountOverflow);
    }
    let capacity = usize::try_from(count).map_err(|_| VectorError::CountOverflow)?;
    let mut records = Vec::with_capacity(capacity);
    for _ in 0..count {
        let code_point = reader.read_u32()?;
        let advance_em = read_float(&mut reader, width)?;
        let x_min = read_float(&mut reader, width)?;
        let y_min = read_float(&mut reader, width)?;
        let x_max = read_float(&mut reader, width)?;
        let y_max = read_float(&mut reader, width)?;
        records.push(GlyphMetrics {
            code_point,
            advance_em,
            bounds: BoundsEm {
                x_min,
                y_min,
                x_max,
                y_max,
            },
        });
    }
    let remaining = reader.remaining();
    if remaining != 0 {
        return Err(VectorError::TrailingBytes { remaining });
    }
    Ok(records)
}

/// Sort runtime per docs/specs/features/17-sorting.md: the platform stable
/// sort is the known-best implementation on this tree, so the runtime adds
/// no algorithm of its own. Sorts in place by code point, ascending, stable;
/// returns the same slice.
pub fn vector_sort_by_code_point(records: &mut [GlyphMetrics]) -> &mut [GlyphMetrics] {
    records.sort_by_key(|record| record.code_point);
    records
}
