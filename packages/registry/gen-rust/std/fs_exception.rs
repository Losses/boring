use crate::runtime::u_string::UString;


#[derive(Debug, Clone, PartialEq)]
pub enum FsError {
    NotFound { operation: UString, path: UString, native_detail: UString },
    PermissionDenied { operation: UString, path: UString, native_detail: UString },
    NotDirectory { operation: UString, path: UString, native_detail: UString },
    AlreadyExists { operation: UString, path: UString, native_detail: UString },
    InvalidInput { operation: UString, path: UString, native_detail: UString },
    IsDirectory { operation: UString, path: UString, native_detail: UString },
    Unavailable { operation: UString, path: UString },
    Other { operation: UString, path: UString, native_detail: UString },
}

impl std::fmt::Display for FsError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FsError::NotFound { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {} not found: {}", operation, path, native_detail)
            }
            FsError::PermissionDenied { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {}: permission denied: {}", operation, path, native_detail)
            }
            FsError::NotDirectory { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {}: not a directory: {}", operation, path, native_detail)
            }
            FsError::AlreadyExists { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {} already exists: {}", operation, path, native_detail)
            }
            FsError::InvalidInput { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {}: invalid input: {}", operation, path, native_detail)
            }
            FsError::IsDirectory { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {} is a directory: {}", operation, path, native_detail)
            }
            FsError::Unavailable { operation, .. } => {
                write!(formatter, "std.Fs.{}: std.Fs is not available on this host", operation)
            }
            FsError::Other { operation, path, native_detail } => {
                write!(formatter, "std.Fs.{}: {}: {}", operation, path, native_detail)
            }
        }
    }
}

impl std::error::Error for FsError {}

impl From<crate::runtime::fs::FsError> for FsError {
    fn from(error: crate::runtime::fs::FsError) -> Self {
        match error.kind {
            crate::runtime::fs::FsErrorKind::NotFound => FsError::NotFound { operation: error.operation, path: error.path, native_detail: error.native_detail },
            crate::runtime::fs::FsErrorKind::PermissionDenied => FsError::PermissionDenied { operation: error.operation, path: error.path, native_detail: error.native_detail },
            crate::runtime::fs::FsErrorKind::NotDirectory => FsError::NotDirectory { operation: error.operation, path: error.path, native_detail: error.native_detail },
            crate::runtime::fs::FsErrorKind::IsDirectory => FsError::IsDirectory { operation: error.operation, path: error.path, native_detail: error.native_detail },
            crate::runtime::fs::FsErrorKind::AlreadyExists => FsError::AlreadyExists { operation: error.operation, path: error.path, native_detail: error.native_detail },
            crate::runtime::fs::FsErrorKind::InvalidInput => FsError::InvalidInput { operation: error.operation, path: error.path, native_detail: error.native_detail },
            crate::runtime::fs::FsErrorKind::Unavailable => FsError::Unavailable { operation: error.operation, path: error.path },
            crate::runtime::fs::FsErrorKind::Other => FsError::Other { operation: error.operation, path: error.path, native_detail: error.native_detail },
        }
    }
}
