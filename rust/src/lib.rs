//! Shared vector format codec for the boring repository: 4 magic bytes, one
//! u32 record count, then one 44-byte record per glyph metric (u32 code
//! point, five f64 values), all big-endian. The Haxe and TypeScript suites
//! read and write the same bytes.
//!
//! Conversion style: no `as` casts and no panicking conversions; every
//! fallible step returns a `VectorError`.

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
pub const RECORD_BYTE_LENGTH: usize = 44;

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

pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    let count = u32::try_from(records.len()).map_err(|_| VectorError::CountOverflow)?;
    let mut bytes = Vec::with_capacity(8 + records.len() * RECORD_BYTE_LENGTH);
    bytes.extend_from_slice(VECTOR_MAGIC);
    bytes.extend_from_slice(&count.to_be_bytes());
    for record in records {
        bytes.extend_from_slice(&record.code_point.to_be_bytes());
        bytes.extend_from_slice(&record.advance_em.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.x_min.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.y_min.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.x_max.to_bits().to_be_bytes());
        bytes.extend_from_slice(&record.bounds.y_max.to_bits().to_be_bytes());
    }
    Ok(bytes)
}

pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        return Err(VectorError::BadMagic);
    }
    let mut reader = VectorReader::new(&bytes[4..]);
    let count = reader.read_u32()?;
    let capacity = usize::try_from(count).map_err(|_| VectorError::CountOverflow)?;
    let mut records = Vec::with_capacity(capacity);
    for _ in 0..count {
        let code_point = reader.read_u32()?;
        let advance_em = reader.read_f64()?;
        let x_min = reader.read_f64()?;
        let y_min = reader.read_f64()?;
        let x_max = reader.read_f64()?;
        let y_max = reader.read_f64()?;
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
