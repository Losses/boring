
// Haxe String storage: owned UTF-16 code units, the Rust target's
// native string type. UString is the owned form, UStr is the borrowed
// slice form, matching the String/&str relationship. Both Deref to
// [u16], so s[i] reads a u16 unit, s.len() returns the unit count,
// and s[a..b] yields a &[u16] slice — extra Index impls are not needed.
//
// Conversions to Rust String (UTF-8) are explicit and named:
//   to_utf8_lossy() -> String     (always succeeds, replaces unpaired surrogates)
//   to_utf8()       -> Option<String> (None on unpaired surrogates)

use std::fmt;
use std::ops::{Deref, DerefMut};

#[derive(Clone, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct UString(Vec<u16>);

#[derive(PartialEq, Eq, PartialOrd, Ord, Hash)]
#[repr(transparent)]
pub struct UStr([u16]);

impl UStr {
    #[inline]
    pub fn new<S: AsRef<[u16]> + ?Sized>(s: &S) -> &UStr {
        unsafe { &*(s.as_ref() as *const [u16] as *const UStr) }
    }

    #[inline]
    pub fn as_slice(&self) -> &[u16] {
        &self.0
    }

    pub fn to_ustring(&self) -> UString {
        UString(self.0.to_vec())
    }

    pub fn to_utf8_lossy(&self) -> String {
        String::from_utf16_lossy(&self.0)
    }

    pub fn to_utf8(&self) -> Option<String> {
        String::from_utf16(&self.0).ok()
    }

    /// Unicode lowercase of the text (String.toLowerCase). Borrowed
    /// receivers (`&UStr`) and owned `UString` (through Deref) both land
    /// here; the result is an owned Haxe String.
    pub fn to_lowercase(&self) -> UString {
        UString(self.to_utf8_lossy().to_lowercase().encode_utf16().collect())
    }

    /// Unicode uppercase of the text (String.toUpperCase). Mirrors
    /// to_lowercase: borrowed receivers and owned UString (through
    /// Deref) both land here; the result is an owned Haxe String.
    pub fn to_uppercase(&self) -> UString {
        UString(self.to_utf8_lossy().to_uppercase().encode_utf16().collect())
    }

    /// The UTF-16 code units as an iterator (String.encodeUtf16). Mirrors
    /// the UString inherent method so `&UStr` receivers resolve too. Items
    /// are owned `u16`, matching the std String encode_utf16 item type.
    pub fn encode_utf16(&self) -> std::iter::Copied<std::slice::Iter<u16>> {
        self.0.iter().copied()
    }

    /// Trim Unicode whitespace from both ends (String.trim). Borrowed
    /// receivers and owned UString (through Deref) both land here; the
    /// result is an owned Haxe String. The u16 domain needs its own
    /// whitespace table because char::from_u32 rejects surrogate halves.
    pub fn trim(&self) -> UString {
        let units = self.as_slice();
        let is_ws = |u: u16| -> bool {
            matches!(u, 0x09..=0x0D | 0x20 | 0x85 | 0xA0 | 0x1680
                | 0x2000..=0x200A | 0x2028 | 0x2029 | 0x202F | 0x205F
                | 0x3000 | 0xFEFF)
        };
        let mut start = 0;
        let mut end = units.len();
        while start < end && is_ws(units[start]) {
            start += 1;
        }
        while end > start && is_ws(units[end - 1]) {
            end -= 1;
        }
        UString(units[start..end].to_vec())
    }

    /// Index of the last occurrence of needle in the unit domain
    /// (String.lastIndexOf). The scanner walks back over the haystack;
    /// starts_with keeps the comparison off a bare slice ==, which the
    /// emission pipeline rewrites (PIT-105).
    pub fn rfind(&self, needle: &UStr) -> Option<usize> {
        let hay = self.as_slice();
        let nee = needle.as_slice();
        if nee.len() > hay.len() {
            return None;
        }
        if nee.is_empty() {
            return Some(hay.len());
        }
        let mut i = hay.len() - nee.len();
        loop {
            if hay[i..].starts_with(nee) {
                return Some(i);
            }
            if i == 0 {
                return None;
            }
            i -= 1;
        }
    }

    /// UTF-8 bytes of the text for byte-oriented sinks such as file
    /// writes; unpaired surrogates degrade exactly like to_utf8_lossy.
    pub fn as_bytes(&self) -> Vec<u8> {
        self.to_utf8_lossy().into_bytes()
    }
}

impl UString {
    pub fn new() -> UString {
        UString(Vec::new())
    }

    pub fn as_ustr(&self) -> &UStr {
        UStr::new(&self.0)
    }

    pub fn to_utf8_lossy(&self) -> String {
        String::from_utf16_lossy(&self.0)
    }

    pub fn to_utf8(&self) -> Option<String> {
        String::from_utf16(&self.0).ok()
    }
}

impl UString {
    /// UTF-16 units to an owned Haxe String, rejecting an unpaired
    /// surrogate the same way String::from_utf16 does (the Err payload is
    /// the unit index of the unpaired lead). (StringBufferFromUtf16)
    pub fn from_utf16(units: &[u16]) -> Result<UString, usize> {
        match String::from_utf16(units) {
            Ok(_) => Ok(UString(units.to_vec())),
            Err(_) => {
                // The declared Err payload is the unit index of the first
                // unpaired surrogate; String::from_utf16 wraps that detail
                // in FromUtf16Error, so rescan here to recover the index.
                let mut i = 0;
                while i < units.len() {
                    let u = units[i];
                    if u >= 0xD800 && u < 0xDC00 {
                        if i + 1 < units.len() && units[i + 1] >= 0xDC00 && units[i + 1] < 0xE000 {
                            i += 2;
                            continue;
                        }
                        return Err(i);
                    }
                    if u >= 0xDC00 && u < 0xE000 {
                        return Err(i);
                    }
                    i += 1;
                }
                Err(units.len())
            }
        }
    }
}

impl From<&str> for UString {
    fn from(s: &str) -> UString {
        UString(s.encode_utf16().collect())
    }
}

impl From<&UStr> for UString {
    fn from(s: &UStr) -> UString {
        UString(s.as_slice().to_vec())
    }
}

impl From<&String> for UString {
    fn from(s: &String) -> UString {
        UString::from(s.as_str())
    }
}

impl Deref for UString {
    type Target = UStr;
    fn deref(&self) -> &UStr {
        UStr::new(&self.0)
    }
}

impl Deref for UStr {
    type Target = [u16];
    fn deref(&self) -> &[u16] {
        self.as_slice()
    }
}

// Cross-form comparisons: business code compares a borrowed view with an
// owned value (and vice versa) in char and prefix checks; the same unit
// slice decides both directions.
impl PartialOrd<UString> for UStr {
    fn partial_cmp(&self, other: &UString) -> Option<std::cmp::Ordering> { self.as_slice().partial_cmp(other.0.as_slice()) }
}

impl PartialOrd<UStr> for UString {
    fn partial_cmp(&self, other: &UStr) -> Option<std::cmp::Ordering> { self.0.as_slice().partial_cmp(other.as_slice()) }
}

impl fmt::Display for UString {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", String::from_utf16_lossy(&self.0))
    }
}

impl fmt::Debug for UString {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "UString({:?})", String::from_utf16_lossy(&self.0))
    }
}

impl fmt::Display for UStr {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}", String::from_utf16_lossy(&self.0))
    }
}

impl fmt::Debug for UStr {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "UStr({:?})", String::from_utf16_lossy(&self.0))
    }
}

impl PartialEq<UString> for &UStr {
    fn eq(&self, other: &UString) -> bool {
        self.as_slice() == other.as_slice()
    }
}

impl PartialEq<&UStr> for UString {
    fn eq(&self, other: &&UStr) -> bool {
        self.as_slice() == other.as_slice()
    }
}

// Resident ABI wrappers (i32 domain) for internal runtime callers
// that compile through the std.UStringRT resident path.
impl UString {
    pub fn u_string_count(s: &UStr) -> i32 {
        i32::try_from(count(s)).unwrap_or(0)
    }
    pub fn u_string_at(s: &UStr, index: i32) -> Option<i32> {
        at(s, u32::try_from(index).unwrap_or(0)).map(|v| i32::try_from(v).unwrap_or(0))
    }
    pub fn u_string_slice(s: &UStr, from: i32, to: i32) -> UString {
        slice(s, from, to)
    }
    pub fn u_string_to_code_points(s: &UStr) -> Vec<i32> {
        to_code_points(s).iter().map(|v| i32::try_from(*v).unwrap_or(0)).collect()
    }
    pub fn u_string_from_code_point(code: i32) -> UString {
        from_code_point(u32::try_from(code).unwrap_or(0))
    }
    pub fn u_string_from_code_points(codes: &Vec<i32>) -> UString {
        let mut inner = Vec::with_capacity(codes.len());
        for v in codes {
            inner.push(u32::try_from(*v).unwrap_or(0));
        }
        from_code_points(&inner)
    }
}

impl UString {
    /// The UTF-16 code units of this string. UString stores units natively,
    /// so this is the slice itself — no re-encoding. (String.encodeUtf16)
    /// Items are owned `u16`, matching the std String encode_utf16 item type.
    pub fn encode_utf16(&self) -> std::iter::Copied<std::slice::Iter<u16>> {
        self.0.iter().copied()
    }
}

// String append (Haxe String += operand) accepts a borrowed Haxe string,
// a borrowed Rust str, and an owned std String.
impl std::ops::AddAssign<&UStr> for UString {
    fn add_assign(&mut self, rhs: &UStr) {
        self.0.extend_from_slice(rhs.as_slice());
    }
}
impl std::ops::AddAssign<&str> for UString {
    fn add_assign(&mut self, rhs: &str) {
        self.0.extend(rhs.encode_utf16());
    }
}
impl std::ops::AddAssign<&UString> for UString {
    fn add_assign(&mut self, rhs: &UString) {
        self.0.extend_from_slice(rhs.as_slice());
    }
}
impl std::ops::AddAssign<&String> for UString {
    fn add_assign(&mut self, rhs: &String) {
        *self += rhs.as_str();
    }
}
impl std::ops::AddAssign<String> for UString {
    fn add_assign(&mut self, rhs: String) {
        *self += rhs.as_str();
    }
}

// Cross-type comparison: a Haxe string compares against Rust str/String by
// UTF-16 unit sequence, the same order the unit-based storage defines.
impl PartialEq<UString> for UStr {
    fn eq(&self, other: &UString) -> bool {
        self.0 == other.0[..]
    }
}
impl PartialEq<UStr> for UString {
    fn eq(&self, other: &UStr) -> bool {
        self.0[..] == other.0
    }
}
impl PartialEq<str> for UStr {
    fn eq(&self, other: &str) -> bool {
        self.0 == other.encode_utf16().collect::<Vec<u16>>()[..]
    }
}
impl PartialEq<UStr> for str {
    fn eq(&self, other: &UStr) -> bool {
        other == self
    }
}
impl PartialEq<String> for UStr {
    fn eq(&self, other: &String) -> bool {
        self == other.as_str()
    }
}
impl PartialEq<UStr> for String {
    fn eq(&self, other: &UStr) -> bool {
        other == self.as_str()
    }
}
// Business ABI adapters: Int arguments arrive unsigned (u32), results
// return u32. slice, substring, and substr keep i32 bounds because
// negative bounds are part of their clamping rule.

pub fn count(s: &UStr) -> u32 {
    let mut i = 0u32;
    let units = s.as_slice();
    let mut pos = 0;
    while pos < units.len() {
        i += 1;
        let cu = units[pos] as u32;
        if cu >= 0xD800 && cu < 0xDC00 && pos + 1 < units.len() {
            let lo = units[pos + 1] as u32;
            if lo >= 0xDC00 && lo < 0xE000 {
                pos += 2;
                continue;
            }
        }
        pos += 1;
    }
    i
}

// The String.length member counts UTF-16 code units on every target
// (stdlib/15). With UStr storage in units, this is just the slice length.
pub fn unit_count(s: &UStr) -> u32 {
    u32::try_from(s.as_slice().len()).unwrap_or(0)
}

// The UTF-16 code-unit vector of a string, built once. Per-character
// loops that read length and per-index units lower against this vector
// instead of rescanning the source on every access.
pub fn units(s: &UStr) -> Vec<u16> {
    s.as_slice().to_vec()
}

// The single UTF-16 unit at `index` read from a precomputed unit vector,
// the O(1) form of String.charCodeAt.
pub fn unit_at_from(units: &[u16], index: u32) -> Option<u32> {
    units.get(usize::try_from(index).unwrap_or(0)).map(|u| u32::from(*u))
}

// The single UTF-16 unit at `index` as an owned one-unit UString, the
// O(1) form of String.charAt; an out-of-range index yields the empty
// string, matching charAt past the end.
pub fn char_at_from(units: &[u16], index: u32) -> UString {
    let i = usize::try_from(index).unwrap_or(0);
    if i < units.len() {
        UString(units[i..i + 1].to_vec())
    } else {
        UString::new()
    }
}

// The code-point read that std.UString.at lowers to: the index counts
// characters and the value is one code point, so a surrogate pair
// occupies one address and yields its combined code point.
pub fn at(s: &UStr, index: u32) -> Option<u32> {
    let mut remaining = index;
    let units = s.as_slice();
    let mut pos = 0;
    while pos < units.len() {
        if remaining == 0 {
            let cu = units[pos] as u32;
            if cu >= 0xD800 && cu < 0xDC00 && pos + 1 < units.len() {
                let lo = units[pos + 1] as u32;
                if lo >= 0xDC00 && lo < 0xE000 {
                    return Some(((cu - 0xD800) << 10 | (lo - 0xDC00)) + 0x10000);
                }
            }
            return Some(cu);
        }
        remaining -= 1;
        let cu = units[pos] as u32;
        if cu >= 0xD800 && cu < 0xDC00 && pos + 1 < units.len() {
            let lo = units[pos + 1] as u32;
            if lo >= 0xDC00 && lo < 0xE000 {
                pos += 2;
                continue;
            }
        }
        pos += 1;
    }
    None
}

// The unit read that String.charCodeAt lowers to (stdlib spec 15): the
// index counts UTF-16 code units, so each half of a surrogate pair
// carries its own address and the value is the unit, never the combined
// code point.
pub fn unit_at(s: &UStr, index: u32) -> Option<u32> {
    s.as_slice().get(usize::try_from(index).unwrap_or(0)).map(|u| u32::from(*u))
}

pub fn split(s: &UStr, separator: &UStr) -> Vec<UString> {
    let source = s.as_slice();
    let needle = separator.as_slice();
    if needle.is_empty() {
        let mut out = Vec::new();
        for unit in source {
            out.push(UString(vec![*unit]));
        }
        return out;
    }
    let mut out = Vec::new();
    let mut start = 0usize;
    let mut cursor = 0usize;
    while cursor + needle.len() <= source.len() {
        if &source[cursor..cursor + needle.len()] == needle {
            out.push(UString(source[start..cursor].to_vec()));
            cursor += needle.len();
            start = cursor;
        } else {
            cursor += 1;
        }
    }
    out.push(UString(source[start..].to_vec()));
    out
}

pub fn slice(s: &UStr, from: i32, to: i32) -> UString {
    let total = count(s);
    let mut start = if from < 0 { 0u32 } else { u32::try_from(from).unwrap_or(0) };
    if start > total {
        start = total;
    }
    let mut stop = u32::try_from(to).unwrap_or(0);
    if stop > total {
        stop = total;
    }
    if to < 0 {
        stop = 0u32;
    }
    if start >= stop {
        return UString::new();
    }
    let mut ordinal = 0u32;
    let mut start_cursor = 0usize;
    let mut cursor = 0usize;
    let units = s.as_slice();
    while ordinal < stop {
        if ordinal == start {
            start_cursor = cursor;
        }
        ordinal += 1;
        let cu = units[cursor] as u32;
        if cu >= 0xD800 && cu < 0xDC00 && cursor + 1 < units.len() {
            let lo = units[cursor + 1] as u32;
            if lo >= 0xDC00 && lo < 0xE000 {
                cursor += 2;
                continue;
            }
        }
        cursor += 1;
    }
    UString(s.as_slice()[start_cursor..cursor].to_vec())
}

pub fn to_code_points(s: &UStr) -> Vec<u32> {
    let mut out = Vec::new();
    let units = s.as_slice();
    let mut pos = 0;
    while pos < units.len() {
        let cu = units[pos] as u32;
        if cu >= 0xD800 && cu < 0xDC00 && pos + 1 < units.len() {
            let lo = units[pos + 1] as u32;
            if lo >= 0xDC00 && lo < 0xE000 {
                out.push(((cu - 0xD800) << 10 | (lo - 0xDC00)) + 0x10000);
                pos += 2;
                continue;
            }
        }
        out.push(cu);
        pos += 1;
    }
    out
}

/// Raw UTF-16 units to an owned Haxe String, with no validity check: a
/// lone surrogate stays an unpaired unit, exactly as Haxe/JS strings
/// carry it. (UStringFromUnits)
pub fn from_units(units: &[u16]) -> UString {
    UString(units.to_vec())
}

pub fn from_code_point(code: u32) -> UString {
    if code <= 0xFFFF {
        UString(vec![code as u16])
    } else if code <= 0x10FFFF {
        let adjusted = code - 0x10000;
        UString(vec![(0xD800 | (adjusted >> 10)) as u16, (0xDC00 | (adjusted & 0x3FF)) as u16])
    } else {
        UString(vec![0x003F]) // replacement character
    }
}

pub fn from_code_points(codes: &Vec<u32>) -> UString {
    let mut units = Vec::with_capacity(codes.len());
    for code in codes {
        if *code <= 0xFFFF {
            units.push(*code as u16);
        } else if *code <= 0x10FFFF {
            let adjusted = code - 0x10000;
            units.push((0xD800 | (adjusted >> 10)) as u16);
            units.push((0xDC00 | (adjusted & 0x3FF)) as u16);
        } else {
            units.push(0x003F);
        }
    }
    UString(units)
}

// substring keeps i32 bounds for the same clamping reason as slice:
// negative bounds are part of the haxe substring rule.
pub fn substring(s: &UStr, from: i32, to: i32) -> UString {
    let units = s.as_slice();
    let len = units.len() as u32;
    let mut start = if from < 0 { 0u32 } else { u32::try_from(from).unwrap_or(0) };
    let mut end = if to < 0 { 0u32 } else { u32::try_from(to).unwrap_or(0) };
    if start > end {
        let tmp = start;
        start = end;
        end = tmp;
    }
    if start >= len {
        return UString::new();
    }
    if end > len {
        end = len;
    }
    UString(units[start as usize..end as usize].to_vec())
}

pub fn substring_from(s: &UStr, from: i32) -> UString {
    let units = s.as_slice();
    let start = if from < 0 { 0u32 } else { u32::try_from(from).unwrap_or(0) };
    if start as usize >= units.len() {
        return UString::new();
    }
    UString(units[start as usize..].to_vec())
}

// substr: pos and len count units per the std rule.
// A negative pos counts from the end; a negative len returns empty.
pub fn substr(s: &UStr, pos: i32, len: Option<i32>) -> UString {
    match len {
        Some(l) if l < 0 => return UString::new(),
        _ => {}
    }
    let units = s.as_slice();
    let total = i64::try_from(units.len()).unwrap_or(0);
    let start = if pos < 0 {
        let back = i64::from(pos).saturating_neg();
        if total > back { total - back } else { 0 }
    } else {
        if i64::from(pos) > total { total } else { i64::from(pos) }
    };
    let end = match len {
        None => total,
        Some(l) => {
            let raw = start + i64::from(l);
            if raw > total { total } else { raw }
        }
    };
    if start >= end {
        return UString::new();
    }
    UString(units[start as usize..end as usize].to_vec())
}

// Haxe Std.parseFloat lowers here.
pub fn parse_f64(s: &UStr) -> f64 {
    let t = s.to_utf8_lossy();
    let t2 = trim_fixed(&t);
    if !valid_decimal_token(t2.as_bytes()) {
        return f64::NAN;
    }
    t2.parse::<f64>().unwrap_or(f64::NAN)
}

pub fn parse_f32(s: &UStr) -> f32 {
    let t = s.to_utf8_lossy();
    let t2 = trim_fixed(&t);
    if !valid_decimal_token(t2.as_bytes()) {
        return f32::NAN;
    }
    t2.parse::<f32>().unwrap_or(f32::NAN)
}

// Haxe Std.parseInt lowers here.
pub fn parse_i32(s: &UStr) -> Option<i32> {
    let t = s.to_utf8_lossy();
    let t2 = trim_fixed(&t);
    let b = t2.as_bytes();
    let mut i = 0;
    let negative = i < b.len() && b[i] == 0x2D;
    if i < b.len() && (b[i] == 0x2B || b[i] == 0x2D) {
        i += 1;
    }
    let hexadecimal = i + 1 < b.len() && b[i] == 0x30 && (b[i + 1] == 0x78 || b[i + 1] == 0x58);
    if hexadecimal {
        i += 2;
    }
    let start = i;
    while i < b.len() {
        let matched = if hexadecimal { b[i].is_ascii_hexdigit() } else { b[i].is_ascii_digit() };
        if !matched {
            break;
        }
        i += 1;
    }
    if i == start || i != b.len() {
        return None;
    }
    let radix = if hexadecimal { 16u32 } else { 10u32 };
    let magnitude = match u32::from_str_radix(&t2[start..], radix) {
        Ok(value) => value,
        Err(_) => return None,
    };
    let signed = if negative { -i64::from(magnitude) } else { i64::from(magnitude) };
    i32::try_from(signed).ok()
}

// The whitespace set of the Haxe scanners.
fn trim_fixed(s: &str) -> &str {
    s.trim_matches(|c: char| c == ' ' || matches!(c, '\t'..='\r'))
}

fn valid_decimal_token(b: &[u8]) -> bool {
    let mut i = 0;
    if i < b.len() && (b[i] == 0x2B || b[i] == 0x2D) {
        i += 1;
    }
    let mut digits = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
        digits += 1;
    }
    if i < b.len() && b[i] == 0x2E {
        i += 1;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
            digits += 1;
        }
    } else if digits == 0 {
        return false;
    }
    if digits == 0 {
        return false;
    }
    if i < b.len() && (b[i] == 0x65 || b[i] == 0x45) {
        i += 1;
        if i < b.len() && (b[i] == 0x2B || b[i] == 0x2D) {
            i += 1;
        }
        let mut exponent_digits = 0;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
            exponent_digits += 1;
        }
        if exponent_digits == 0 {
            return false;
        }
    }
    i == b.len()
}

// String.indexOf with a start position (stdlib spec 15): the start and
// the returned index both count UTF-16 code units.
pub fn find_from(s: &UStr, needle: &UStr, start: i32) -> i32 {
    let units = s.as_slice();
    let n = needle.as_slice();
    let start_unit = if start < 0 { 0u32 } else { u32::try_from(start).unwrap_or(u32::MAX) };
    let begin = usize::try_from(start_unit).unwrap_or(units.len());
    if begin >= units.len() {
        return -1;
    }
    let rest = &units[begin..];
    // naive search
    if n.is_empty() {
        return i32::try_from(start_unit).unwrap_or(-1);
    }
    if rest.len() >= n.len() {
        for i in 0..=rest.len() - n.len() {
            if &rest[i..i + n.len()] == n {
                return i32::try_from(u32::try_from(begin + i).unwrap_or(0)).unwrap_or(-1);
            }
        }
    }
    -1
}

fn byte_to_unit(s: &str, byte: usize) -> u32 {
    let mut units = 0u32;
    for (b, c) in s.char_indices() {
        if b >= byte {
            break;
        }
        units += u32::try_from(c.len_utf16()).unwrap_or(0);
    }
    units
}

