#[derive(Debug, Clone, PartialEq)]
pub enum UStringFault {
    InvalidCodePoint { code: u32 },
    UnpairedSurrogate { unit: u32 },
}

impl std::fmt::Display for UStringFault {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            UStringFault::InvalidCodePoint { code } => {
                write!(formatter, "invalid code point: {}", code)
            }
            UStringFault::UnpairedSurrogate { unit } => {
                write!(formatter, "unpaired surrogate: {}", unit)
            }
        }
    }
}

impl std::error::Error for UStringFault {}
