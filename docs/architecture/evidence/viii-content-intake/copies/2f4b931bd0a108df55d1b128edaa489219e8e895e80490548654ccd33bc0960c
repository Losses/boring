use crate::registry::json::JsonValue;
use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;


#[derive(Debug, Clone, PartialEq)]
pub struct Release {
    pub owner: UString,
    pub repo: UString,
    pub version: UString,
    pub name: UString,
    pub license: Option<UString>,
    pub readme: UString,
    pub platform: UString,
    pub url: Option<UString>,
    pub digest: UString,
    pub archive: Option<UString>,
    pub package_swift: Option<UString>,
    pub pubspec: Option<JsonValue>,
    pub group_id: Option<UString>,
    pub artifacts: Vec<UString>,
    pub artifact_urls: Vec<UString>,
}

impl Release {
    pub fn new(o: &UStr, r: &UStr, v: &UStr, p: &UStr, n: &UStr, l: Option<UString>, read: &UStr) -> Self {
        Self {
            owner: o.to_ustring(),
            repo: r.to_ustring(),
            version: v.to_ustring(),
            name: n.to_ustring(),
            license: match &(l) { Some(v) => Some(v.to_ustring()), None => None },
            readme: read.to_ustring(),
            platform: p.to_ustring(),
            url: None,
            digest: UString::from(""),
            archive: None,
            package_swift: None,
            pubspec: None,
            group_id: None,
            artifacts: vec![],
            artifact_urls: vec![],
        }
    }
}
