use crate::registry::core::Core;
use crate::registry::core::InputRecord;
use crate::registry::core_exception::CoreFault;
use crate::runtime::fs::Fs;
use crate::runtime::u_string;
use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;
use crate::std::fs_exception::FsError;
use crate::std::path::Path;


#[derive(Debug, Clone, PartialEq)]
pub enum MainMainFault {
    FsErrorFault(crate::std::fs_exception::FsError),
    CoreFaultFault(crate::registry::core_exception::CoreFault),
}
impl std::fmt::Display for MainMainFault {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MainMainFault::FsErrorFault(value) => write!(formatter, "{}", value),
            MainMainFault::CoreFaultFault(value) => write!(formatter, "{}", value),
        }
    }
}

impl From<MainMainFault> for crate::std::fs_exception::FsError {
    fn from(value: MainMainFault) -> Self {
        match value {
            MainMainFault::FsErrorFault(value) => value,
            _ => panic!("fault union converted to an unrelated fault"),
        }
    }
}

impl From<MainMainFault> for crate::registry::core_exception::CoreFault {
    fn from(value: MainMainFault) -> Self {
        match value {
            MainMainFault::CoreFaultFault(value) => value,
            _ => panic!("fault union converted to an unrelated fault"),
        }
    }
}

impl From<crate::runtime::fs::FsError> for MainMainFault {
    fn from(value: crate::runtime::fs::FsError) -> Self {
        MainMainFault::FsErrorFault(crate::std::fs_exception::FsError::from(value))
    }
}

impl From<crate::registry::core_exception::CoreFault> for MainMainFault {
    fn from(value: crate::registry::core_exception::CoreFault) -> Self {
        MainMainFault::CoreFaultFault(value)
    }
}

#[derive(Clone, Copy)]
pub struct Main;

impl Main {
    pub(crate) fn main_read_tree(root: &UStr, rel: &UStr, out: &mut Vec<InputRecord>) -> Result<(), FsError> {
        let full = if rel == UString::from("") { (root.to_ustring()).clone() } else { Path::path_join(root, rel).to_ustring() };
        if Fs::is_directory(full.as_ustr()) {
            let names = Fs::read_dir(full.as_ustr())?;
            for name in &names {
                let _ = Main::main_read_tree(root, if rel == UString::from("") { name.to_ustring() } else { UString::from(format!("{}", { let mut __s = UString::new(); __s += rel; __s += &(UString::from("/")); __s += name.as_ustr(); __s }).as_str()) }.as_ustr(), out)?;
            }
        } else {
            out.push(InputRecord { path: rel.to_ustring(), content: Fs::read_text(full.as_ustr())?.clone(), input_record: 1 });
        }
        Ok(())
    }

    pub fn main_main() -> Result<(), MainMainFault> {
        let config = Core::core_parse_args(&u_string::args_from_host()).map_err(|e| MainMainFault::CoreFaultFault(e))?;
        if Fs::exists((config.output).to_ustring().as_ustr()) && (i32::from_ne_bytes(((u32::try_from((Fs::read_dir((config.output).to_ustring().as_ustr())?.len()) & 0xFFFF_FFFF).unwrap_or(0)) as i32).to_ne_bytes())) > (0) {
            return Err(MainMainFault::CoreFaultFault(CoreFault::Config { text: UString::from("output directory is not empty") }));
        }
        let mut records: Vec<InputRecord> = vec![];
        if !Fs::exists((config.tree).to_ustring().as_ustr()) {
            return Err(MainMainFault::CoreFaultFault(CoreFault::Config { text: UString::from(format!("{}", { let mut __s = UString::new(); __s += (config.tree).to_ustring().as_ustr(); __s += &(UString::from(": missing tree")); __s }).as_str()) }));
        }
        let _ = Main::main_read_tree((config.tree).to_ustring().as_ustr(), UStr::new(&[]), &mut records).map_err(|e| MainMainFault::FsErrorFault(e))?;
        let files = Core::core_generate(&records, (config).clone()).map_err(|e| MainMainFault::CoreFaultFault(e))?;
        for file in &files {
            let p = Path::path_join((config.output).to_ustring().as_ustr(), (file.path).to_ustring().as_ustr());
            let _ = Fs::make_dirs(Path::path_dirname(p.as_ustr()).as_ustr())?;
            let _ = Fs::write_text(p.as_ustr(), (file.content).to_ustring().as_ustr())?;
        }
        Ok(())
    }
}
