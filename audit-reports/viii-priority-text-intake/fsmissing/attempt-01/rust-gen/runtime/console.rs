use crate::runtime::u_string::UStr;

pub struct Console;

impl Console {
    pub fn log(message: &UStr) {
        println!("{}", message.to_utf8_lossy());
    }
}
