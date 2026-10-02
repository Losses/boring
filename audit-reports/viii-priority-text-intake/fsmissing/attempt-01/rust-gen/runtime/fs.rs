pub struct Fs;

use crate::runtime::u_string::{UStr, UString};

fn fail(path: &UStr, error: std::io::Error) -> ! {
    panic!("{}: {}", path.to_utf8_lossy(), error);
}

impl Fs {
    pub fn exists(path: &UStr) -> bool {
        std::path::Path::new(path.to_utf8_lossy().as_str()).exists()
    }

    pub fn read_text(path: &UStr) -> UString {
        let bytes = std::fs::read(path.to_utf8_lossy().as_str()).unwrap_or_else(|e| fail(path, e));
        UString::from(String::from_utf8_lossy(&bytes).into_owned().as_str())
    }

    pub fn write_text(path: &UStr, data: &UStr) {
        std::fs::write(path.to_utf8_lossy().as_str(), data.as_bytes()).unwrap_or_else(|e| fail(path, e));
    }

    pub fn append_text(path: &UStr, data: &UStr) {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path.to_utf8_lossy().as_str())
            .unwrap_or_else(|e| fail(path, e));
        file.write_all(&data.as_bytes())
            .unwrap_or_else(|e| fail(path, e));
    }

    pub fn make_dirs(path: &UStr) {
        std::fs::create_dir_all(path.to_utf8_lossy().as_str()).unwrap_or_else(|e| fail(path, e));
    }

    pub fn read_dir(path: &UStr) -> Vec<UString> {
        let entries = std::fs::read_dir(path.to_utf8_lossy().as_str()).unwrap_or_else(|e| fail(path, e));
        let mut names = Vec::new();
        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(e) => fail(path, e),
            };
            names.push(UString::from(entry.file_name().to_string_lossy().into_owned().as_str()));
        }
        names
    }

    pub fn is_directory(path: &UStr) -> bool {
        match std::fs::metadata(path.to_utf8_lossy().as_str()) {
            Ok(metadata) => metadata.is_dir(),
            Err(_) => false,
        }
    }
}
