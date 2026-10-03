use crate::runtime::u_string::UString;


#[derive(Debug, Clone, PartialEq)]
pub enum CoreFault {
    Config { text: UString },
    Tree { text: UString },
}

impl std::fmt::Display for CoreFault {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CoreFault::Config { text } => {
                write!(formatter, "{}", text)
            }
            CoreFault::Tree { text } => {
                write!(formatter, "{}", text)
            }
        }
    }
}

impl std::error::Error for CoreFault {}
