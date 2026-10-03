use crate::runtime::u_string::UString;

#[derive(Clone)]
pub struct Exception;

impl Exception {
    // The haxe.Exception base carries a message string on other targets; the
    // rust marker form has no storage, so a message read lowers to the empty
    // string, matching the kotlin `?: ""` mapping.
    pub fn get_message(&self) -> UString {
        UString::new()
    }
}
