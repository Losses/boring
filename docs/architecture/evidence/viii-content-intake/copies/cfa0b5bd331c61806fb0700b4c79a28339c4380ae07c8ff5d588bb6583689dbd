use crate::runtime::u_string;
use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;
use std::fmt::Write;


#[derive(Clone, Copy)]
pub struct StringTools;

impl StringTools {
    pub fn string_tools_is_space(s: &UStr, pos: i32) -> bool {
    let __units = u_string::units(&s);
    let __count = u_string::unit_count(&s);
        if i32::from_ne_bytes(((__count) as i32).to_ne_bytes()) == 0 || (pos) < (0) || (pos) >= i32::from_ne_bytes(((__count) as i32).to_ne_bytes()) {
            return false;
        }
        let c = u_string::unit_at_from(&__units, u32::from_ne_bytes(((pos) as u32).to_ne_bytes())).unwrap_or(0);
        return (c) > (8) && (c) < (14) || c == 32;
    }

    pub fn string_tools_ltrim(s: &UStr) -> UString {
        let l = i32::from_ne_bytes(((u_string::unit_count(&(s))) as i32).to_ne_bytes());
        let mut r = 0i32;
        while (r) < (l) && StringTools::string_tools_is_space(s, r) {
            r = i32::wrapping_add(r, 1);
        }
        return if r > (0) { u_string::substr(&s, r, Some(i32::wrapping_sub(l, r))).to_ustring() } else { s.to_ustring() };
    }

    pub fn string_tools_rtrim(s: &UStr) -> UString {
        let l = i32::from_ne_bytes(((u_string::unit_count(&(s))) as i32).to_ne_bytes());
        let mut r = 0i32;
        while (r) < (l) && StringTools::string_tools_is_space(s, i32::wrapping_sub(i32::wrapping_sub(l, r), 1)) {
            r = i32::wrapping_add(r, 1);
        }
        return if r > (0) { u_string::substr(&s, 0i32, Some(i32::wrapping_sub(l, r))).to_ustring() } else { s.to_ustring() };
    }

    pub fn string_tools_lpad(s: &UStr, c: &UStr, l: i32) -> UString {
        if i32::from_ne_bytes(((u_string::unit_count(&(c))) as i32).to_ne_bytes()) <= 0 {
            return s.to_ustring();
        }
        let mut buf_b = UString::new();
        let remaining = i32::wrapping_sub(l, i32::from_ne_bytes(((u_string::unit_count(&(s))) as i32).to_ne_bytes()));
        while (i32::from_ne_bytes(((u_string::unit_count(&(buf_b))) as i32).to_ne_bytes())) < (remaining) {
            buf_b += &(c.to_string());
        }
        buf_b += &(s.to_string());
        return buf_b;
    }

    pub fn string_tools_rpad(s: &UStr, c: &UStr, l: i32) -> UString {
        if i32::from_ne_bytes(((u_string::unit_count(&(c))) as i32).to_ne_bytes()) <= 0 {
            return s.to_ustring();
        }
        let mut buf_b = UString::new();
        buf_b += &(s.to_string());
        let remaining = i32::wrapping_sub(l, i32::from_ne_bytes(((u_string::unit_count(&(s))) as i32).to_ne_bytes()));
        while (i32::from_ne_bytes(((u_string::unit_count(&(buf_b))) as i32).to_ne_bytes())) < (remaining) {
            buf_b += &(c.to_string());
        }
        return buf_b;
    }

    pub fn string_tools_replace(s: &UStr, sub: &UStr, by: &UStr) -> UString {
        return UString::from(format!("{}", { let joined = u_string::split(&s, &sub); let mut out = String::new(); let n = joined.len(); let mut index = 0usize; while index < n { if index > 0 { out.push_str(&(by).to_utf8_lossy()); } let _ = write!(out, "{}", joined[index]); index += 1; } UString::from(out.as_str()) }).as_str());
    }
}
