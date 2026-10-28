pub struct Fs;

use crate::runtime::u_string::{UStr, UString};

/// One normalized kind of a host filesystem failure. The host error set is
/// open and OS-specific, so std.Fs identity is (operation, path, kind) and
/// the host text is display detail only.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FsErrorKind {
    NotFound,
    PermissionDenied,
    NotDirectory,
    IsDirectory,
    AlreadyExists,
    InvalidInput,
    Unavailable,
    Other,
}

/// A host filesystem failure carried as a value. `operation`/`path`/`kind`
/// are the comparable identity; `native_detail` is the raw host error text,
/// empty for Unavailable (a synthesized kind with no host text).
#[derive(Debug, Clone, PartialEq)]
pub struct FsError {
    pub operation: UString,
    pub path: UString,
    pub kind: FsErrorKind,
    pub native_detail: UString,
}

impl FsError {
    fn classify(error: &std::io::Error) -> FsErrorKind {
        match error.kind() {
            std::io::ErrorKind::NotFound => FsErrorKind::NotFound,
            std::io::ErrorKind::PermissionDenied => FsErrorKind::PermissionDenied,
            std::io::ErrorKind::NotADirectory => FsErrorKind::NotDirectory,
            std::io::ErrorKind::IsADirectory => FsErrorKind::IsDirectory,
            std::io::ErrorKind::AlreadyExists => FsErrorKind::AlreadyExists,
            std::io::ErrorKind::InvalidInput => FsErrorKind::InvalidInput,
            std::io::ErrorKind::Unsupported => FsErrorKind::Unavailable,
            _ => FsErrorKind::Other,
        }
    }

    fn host(operation: &str, path: &UStr, error: std::io::Error) -> FsError {
        let path_text = path.to_utf8_lossy();
        let kind = FsError::classify(&error);
        // Unavailable is the synthesized kind: it carries no host text.
        let native_detail = match kind {
            FsErrorKind::Unavailable => String::new(),
            _ => error.to_string(),
        };
        FsError {
            operation: UString::from(operation),
            path: UString::from(path_text.as_str()),
            kind,
            native_detail: UString::from(native_detail.as_str()),
        }
    }
}

impl std::fmt::Display for FsError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
        write!(formatter, "{}: {}", self.path, self.native_detail)
    }
}

impl std::error::Error for FsError {}

impl Fs {
    pub fn exists(path: &UStr) -> bool {
        std::path::Path::new(path.to_utf8_lossy().as_str()).exists()
    }

    pub fn read_text(path: &UStr) -> Result<UString, FsError> {
        let bytes = std::fs::read(path.to_utf8_lossy().as_str())
            .map_err(|e| FsError::host("readText", path, e))?;
        Ok(UString::from(String::from_utf8_lossy(&bytes).into_owned().as_str()))
    }

    pub fn write_text(path: &UStr, data: &UStr) -> Result<(), FsError> {
        std::fs::write(path.to_utf8_lossy().as_str(), data.as_bytes())
            .map_err(|e| FsError::host("writeText", path, e))
    }

    pub fn append_text(path: &UStr, data: &UStr) -> Result<(), FsError> {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path.to_utf8_lossy().as_str())
            .map_err(|e| FsError::host("appendText", path, e))?;
        file.write_all(&data.as_bytes())
            .map_err(|e| FsError::host("appendText", path, e))
    }

    pub fn make_dirs(path: &UStr) -> Result<(), FsError> {
        std::fs::create_dir_all(path.to_utf8_lossy().as_str())
            .map_err(|e| FsError::host("makeDirs", path, e))
    }

    pub fn read_dir(path: &UStr) -> Result<Vec<UString>, FsError> {
        let entries = std::fs::read_dir(path.to_utf8_lossy().as_str())
            .map_err(|e| FsError::host("readDir", path, e))?;
        let mut names = Vec::new();
        for entry in entries {
            // F7 (Claude review): match-rewrite removes the loop-body closure so
            // reference/rust stays closure-free (loop-structure contract).
            let entry = match entry { Ok(e) => e, Err(e) => return Err(FsError::host("readDir", path, e)) };
            names.push(UString::from(entry.file_name().to_string_lossy().into_owned().as_str()));
        }
        Ok(names)
    }

    pub fn is_directory(path: &UStr) -> bool {
        match std::fs::metadata(path.to_utf8_lossy().as_str()) {
            Ok(metadata) => metadata.is_dir(),
            Err(_) => false,
        }
    }

    pub fn delete_file(path: &UStr) -> Result<(), FsError> {
        std::fs::remove_file(path.to_utf8_lossy().as_str())
            .map_err(|e| FsError::host("deleteFile", path, e))
    }

    pub fn rename(from: &UStr, to: &UStr) -> Result<(), FsError> {
        std::fs::rename(from.to_utf8_lossy().as_str(), to.to_utf8_lossy().as_str())
            .map_err(|e| FsError::host("rename", from, e))
    }
}
