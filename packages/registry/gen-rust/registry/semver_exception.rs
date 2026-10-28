use crate::runtime::u_string::UString;


#[derive(Debug, Clone, PartialEq)]
pub enum SemverFault {
    InvalidCore { version: UString },
    InvalidExtension { version: UString },
}

impl std::fmt::Display for SemverFault {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SemverFault::InvalidCore { version } => {
                write!(formatter, "invalid version core: {}", version)
            }
            SemverFault::InvalidExtension { version } => {
                write!(formatter, "invalid prerelease or build metadata: {}", version)
            }
        }
    }
}

impl std::error::Error for SemverFault {}
