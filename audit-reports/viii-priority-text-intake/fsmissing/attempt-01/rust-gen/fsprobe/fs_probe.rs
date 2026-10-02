use crate::runtime::console::Console;
use crate::runtime::fs::Fs;
use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;


#[derive(Clone, Copy)]
pub struct FsProbe;

impl FsProbe {
    pub fn fs_probe_missing_root() -> UString {
        return UString::from("out/fs-missing/probe/definitely-missing").to_ustring();
    }

    pub fn fs_probe_say(label: &UStr, text: &UStr) {
        Console::log(UString::from(format!("{}", { let mut __s = UString::new(); __s += label; __s += &(UString::from("|")); __s += text; __s }).as_str()).as_ustr());
    }

    pub fn fs_probe_message_of(error: FsProbeFault) -> UString {
        return if false { UString::from("<not-caught>") } else { UString::from(format!("{}", {
    let bound = (error).clone();
    format!("{}", bound)
}).as_str()) };
    }

    pub fn fs_probe_run() {
        let missing = { let mut __s = UString::new(); __s += FsProbe::fs_probe_missing_root().as_ustr(); __s += &(UString::from("/no-such-file.txt")); __s };
        FsProbe::fs_probe_say(UStr::new(&[109,48]), UStr::new(&[112,114,111,98,101,45,115,116,97,114,116]));
        let dir = Fs::is_directory(missing.as_ustr());
        FsProbe::fs_probe_say(UStr::new(&[109,49]), UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("isDirectory-returned|")); __s += UString::from((dir).to_string().as_str()).as_ustr(); __s }).as_str()).as_ustr());
        let mut caught = false;
        let mut name = UString::from("<not-caught>").to_ustring();
        let mut message = UString::from("<not-caught>").to_ustring();
        let __outcome: Result<(), FsProbeFault> = (|| {
            let text = Fs::read_text(missing.as_ustr());
            FsProbe::fs_probe_say(UStr::new(&[109,50]), UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("readText-returned|")); __s += text.as_ustr(); __s }).as_str()).as_ustr());
            Ok(())
        })();
        match __outcome {
            Ok(_) => {}
            Err(error) => {
                caught = true;
                name = UString::from("haxe.Exception").to_ustring();
                message = FsProbe::fs_probe_message_of((error).clone());
            }
        }
        FsProbe::fs_probe_say(UStr::new(&[109,51]), UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("readText-catch-ran|")); __s += UString::from((caught).to_string().as_str()).as_ustr(); __s }).as_str()).as_ustr());
        FsProbe::fs_probe_say(UStr::new(&[109,52]), UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("caught-declared-class|")); __s += name.as_ustr(); __s }).as_str()).as_ustr());
        FsProbe::fs_probe_say(UStr::new(&[109,53]), UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("caught-message|")); __s += message.as_ustr(); __s }).as_str()).as_ustr());
        FsProbe::fs_probe_say(UStr::new(&[109,54]), UStr::new(&[117,110,99,97,117,103,104,116,45,114,101,103,105,111,110,45,115,116,97,114,116]));
        let escaped = Fs::read_text(missing.as_ustr());
        FsProbe::fs_probe_say(UStr::new(&[109,55]), UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("uncaught-region-returned|")); __s += escaped.as_ustr(); __s }).as_str()).as_ustr());
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FsProbeFault {
    pub message: String,
}
impl FsProbeFault {
    pub fn new(message: &str) -> Self {
        Self { message: message.to_string() }
    }
}
impl std::fmt::Display for FsProbeFault {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{}", self.message)
    }
}
impl std::error::Error for FsProbeFault {}
