package rustcompiler;

#if (macro || reflaxe_runtime)
/**
    Headerless runtime shim sources for the standard library, emitted on
    demand under the configured runtime package.
**/
class RustRuntime {
    public static final EXCEPTION_SOURCE = '
#[derive(Clone)]
pub struct Exception;

impl Exception {
    // The haxe.Exception base carries a message string on other targets; the
    // rust marker form has no storage, so a message read lowers to the empty
    // string, matching the kotlin `?: ""` mapping.
    pub fn get_message(&self) -> String {
        String::new()
    }
}
';

    /** The Functional shim is precision-parameterized: sum_of_float
        accumulates at the element Float's width, so the f32 mode binds
        f32 and the f64 mode binds f64 (feature spec 23). */
    public static function functionalSource():String {
        final f = FloatPrecision.isF32() ? "f32" : "f64";
        return '
pub struct Functional;

impl Functional {
    pub fn for_each<T, F>(arr: &Vec<T>, mut f: F)
    where
        F: FnMut(&T),
    {
        for item in arr {
            f(item);
        }
    }

    pub fn sum_of_float<T, F>(arr: &Vec<T>, mut f: F) -> $f
    where
        F: FnMut(&T) -> $f,
    {
        let mut total = 0.0;
        for item in arr {
            total += f(item);
        }
        total
    }
}
';
    }


    public static final BYTES_BUFFER_SOURCE = '
pub struct BytesBuffer {
    bytes: Vec<u8>,
}

impl BytesBuffer {
    pub fn new() -> Self {
        Self { bytes: Vec::new() }
    }

    pub fn add_byte(&mut self, byte: u8) {
        self.bytes.push(byte);
    }

    pub fn add(&mut self, bytes: &Vec<u8>) {
        self.bytes.extend_from_slice(bytes);
    }

    pub fn get_bytes(&self) -> Vec<u8> {
        self.bytes.clone()
    }
}
';

    public static final FP_HELPER_SOURCE = '
pub struct FPHelper;

pub struct Int64Halves {
    pub high: u32,
    pub low: u32,
}

impl FPHelper {
    pub fn format_float(v: f64) -> String {
        if v.is_nan() { return "NaN".to_string(); }
        if v == f64::INFINITY { return "Infinity".to_string(); }
        if v == f64::NEG_INFINITY { return "-Infinity".to_string(); }
        Self::format_float_text(v.to_string())
    }

    pub fn format_float_f32(v: f32) -> String {
        if v.is_nan() { return "NaN".to_string(); }
        if v == f32::INFINITY { return "Infinity".to_string(); }
        if v == f32::NEG_INFINITY { return "-Infinity".to_string(); }
        Self::format_float_text(v.to_string())
    }

    fn format_float_text(mut text: String) -> String {
        if text == "0" || text == "-0" { return "0".to_string(); }
        text = text.replace("E", "e");
        let negative = text.starts_with("-");
        if negative { text = text[1..].to_string(); }
        let parts: Vec<&str> = text.split("e").collect();
        let mantissa = parts[0].to_string();
        let exponent: i32 = if parts.len() == 2 { parts[1].parse().unwrap_or(0) } else { 0 };
        let dot = mantissa.find(".").unwrap_or(mantissa.len());
        let mut digits = mantissa.replace(".", "");
        let mut position = dot as i32 + exponent;
        while digits.len() > 1 && digits.starts_with("0") { digits.remove(0); position -= 1; }
        if position >= -5 && position <= 21 {
            let mut plain = if position <= 0 { format!("0.{}{}", "0".repeat((-position) as usize), digits) }
                else if position as usize >= digits.len() { format!("{}{}", digits, "0".repeat(position as usize - digits.len())) }
                else { format!("{}.{}", &digits[..position as usize], &digits[position as usize..]) };
            while plain.contains(".") && plain.ends_with("0") { plain.pop(); }
            if plain.ends_with(".") { plain.pop(); }
            return if negative { format!("-{}", plain) } else { plain };
        }
        while digits.len() > 1 && digits.ends_with("0") { digits.pop(); }
        let sci = position - 1;
        let mantissa = if digits.len() == 1 { digits } else { format!("{}.{}", &digits[..1], &digits[1..]) };
        if negative { format!("-{}e{}{}", mantissa, if sci >= 0 { "+" } else { "" }, sci) }
        else { format!("{}e{}{}", mantissa, if sci >= 0 { "+" } else { "" }, sci) }
    }

    pub fn float_to_i32(v: f64) -> i32 {
        v as i32
    }

    pub fn i32_to_float(v: i32) -> f64 {
        v as f64
    }

    pub fn f32_to_i32(v: f32) -> i32 {
        i32::from_ne_bytes(v.to_bits().to_ne_bytes())
    }

    pub fn i32_to_f32(v: i32) -> f32 {
        f32::from_bits(v as u32)
    }

    pub fn i64_to_double(low: u32, high: u32) -> f64 {
        let h = high.to_be_bytes();
        let l = low.to_be_bytes();
        let bits = u64::from_be_bytes([h[0], h[1], h[2], h[3], l[0], l[1], l[2], l[3]]);
        f64::from_bits(bits)
    }

    pub fn double_to_i64(v: f64) -> Int64Halves {
        let bytes = v.to_bits().to_be_bytes();
        let high = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        let low = u32::from_be_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]);
        Int64Halves { high, low }
    }

    // Binary32 variants of the two value edges: the same 8 wire bytes
    // decode to the f64 value, then round once to the module real; the
    // reverse widens losslessly before the bit conversion. Only the
    // float-precision=f32 lane references them (feature spec 23).
    pub fn i64_to_f32(low: u32, high: u32) -> f32 {
        f32::from_bits(Self::f64_halves_to_f32_bits(low, high))
    }

    fn f64_halves_to_f32_bits(low: u32, high: u32) -> u32 {
        let sign = high >> 31;
        let exp11 = high >> 20 & 2047;
        if exp11 == 2047 {
            if (high & 1048575) == 0 && low == 0 {
                return sign << 31 | 2139095040;
            }
            return sign << 31 | 2139095040 | 4194304 | high >> 10 & 1023;
        }
        if exp11 == 0 {
            return sign << 31;
        }
        let mant_high = high & 1048575;
        let mut sig24 = 8388608 | mant_high << 3 | low >> 29;
        let dropped = low & 536870911;
        let half = 268435456;
        if dropped > half || dropped == half && (sig24 & 1) == 1 {
            sig24 = sig24.wrapping_add(1);
        }
        let mut e2 = exp11;
        if sig24 == 16777216 {
            sig24 = 8388608;
            e2 = e2.wrapping_add(1);
        }
        if e2 >= 1151 {
            return sign << 31 | 2139095040;
        }
        if e2 >= 897 {
            return sign << 31 | (e2 - 896) << 23 | sig24 & 8388607;
        }
        sign << 31 | Self::subnormal_target(mant_high, low, 896 - e2)
    }

    fn subnormal_target(mant_high: u32, low: u32, k: u32) -> u32 {
        if k >= 24 { return 0; }
        let top = (1048576 | mant_high) << 2 | low >> 30;
        let rest = low & 1073741823;
        let half_rest = 536870912;
        let mut h = if k == 0 { top } else { top >> k };
        if k == 0 {
            if rest > half_rest || rest == half_rest && (h & 1) == 1 { h = h.wrapping_add(1); }
        } else {
            let r = top & ((1 << k) - 1);
            let half_r = 1 << (k - 1);
            if r > half_r || r == half_r && rest > 0 || r == half_r && rest == 0 && (h & 1) == 1 { h = h.wrapping_add(1); }
        }
        if h == 8388608 { return 8388608; }
        h
    }

    pub fn f32_to_i64(v: f32) -> Int64Halves {
        Self::double_to_i64(f64::from(v))
    }
}
';

    public static final CONSOLE_SOURCE = '
pub struct Console;

impl Console {
    pub fn log(message: &str) {
        println!("{message}");
    }
}
';

    public static final PROCESS_SOURCE = '
pub struct Process;

impl Process {
    pub fn exit(code: i32) -> ! {
        std::process::exit(code);
    }
}
';

    /**
        The process-local environment overlay of std.Env
        (docs/specs/stdlib/17-platform-modules.md). Rust can write the
        process environment, but cargo runs the generated tests in
        parallel and std::env::set_var is unsafe under concurrency
        (edition 2024); every std.Env call routes through this overlay,
        which records the writes and falls back to the host for the keys
        it has never seen. Get and set therefore operate on one
        environment view.
    **/
    public static final ENV_SOURCE = '
use std::cell::RefCell;
use std::collections::HashMap;
use std::collections::HashSet;

thread_local! {
    static SET_VALUES: RefCell<HashMap<String, String>> = RefCell::new(HashMap::new());
    static REMOVED_KEYS: RefCell<HashSet<String>> = RefCell::new(HashSet::new());
}

pub struct Env;

impl Env {
    pub fn get(key: &str) -> Option<String> {
        if REMOVED_KEYS.with(|removed| removed.borrow().contains(key)) {
            return None;
        }
        if let Some(value) = SET_VALUES.with(|set| set.borrow().get(key).cloned()) {
            return Some(value);
        }
        std::env::var(key).ok()
    }

    pub fn set(key: &str, value: &str) {
        REMOVED_KEYS.with(|removed| {
            removed.borrow_mut().remove(key);
        });
        SET_VALUES.with(|set| {
            set.borrow_mut().insert(key.to_string(), value.to_string());
        });
    }

    pub fn remove(key: &str) {
        SET_VALUES.with(|set| {
            set.borrow_mut().remove(key);
        });
        REMOVED_KEYS.with(|removed| {
            removed.borrow_mut().insert(key.to_string());
        });
    }
}
';

    /**
        The std.Fs backing module (docs/specs/stdlib/17-platform-modules.md).
        Each method maps to the std::fs operation the spec rules; a
        failing operation panics with the path and the host error text,
        the target's exception mapping. The calls lower through the normal
        shim path, so the calling file carries no host import.
    **/
    public static final FS_SOURCE = '
pub struct Fs;

fn fail(path: &str, error: std::io::Error) -> ! {
    panic!("{}: {}", path, error);
}

impl Fs {
    pub fn exists(path: &str) -> bool {
        std::path::Path::new(path).exists()
    }

    pub fn read_text(path: &str) -> String {
        let bytes = std::fs::read(path).unwrap_or_else(|e| fail(path, e));
        String::from_utf8_lossy(&bytes).into_owned()
    }

    pub fn write_text(path: &str, data: &str) {
        std::fs::write(path, data).unwrap_or_else(|e| fail(path, e));
    }

    pub fn append_text(path: &str, data: &str) {
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .unwrap_or_else(|e| fail(path, e));
        file.write_all(data.as_bytes())
            .unwrap_or_else(|e| fail(path, e));
    }

    pub fn make_dirs(path: &str) {
        std::fs::create_dir_all(path).unwrap_or_else(|e| fail(path, e));
    }

    pub fn read_dir(path: &str) -> Vec<String> {
        let entries = std::fs::read_dir(path).unwrap_or_else(|e| fail(path, e));
        let mut names = Vec::new();
        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(e) => fail(path, e),
            };
            names.push(entry.file_name().to_string_lossy().into_owned());
        }
        names
    }

    pub fn is_directory(path: &str) -> bool {
        match std::fs::metadata(path) {
            Ok(metadata) => metadata.is_dir(),
            Err(_) => false,
        }
    }
}
';

    public static final TEST_SOURCE = [
        'use std::cell::RefCell;',
        'use std::fs::OpenOptions;',
        'use std::io::Write;',
        '',
        'thread_local! {',
        '    static CURRENT_TEST: RefCell<Option<String>> = RefCell::new(None);',
        '}',
        '',
        '// Host edges of the test runtime (P6): the runner state, the language',
        '// raise, and the result-file edge. The assertion checks and canonical',
        '// formatting live in runtime.TestCore, compiled beside this module.',
        'pub fn current_test_id() -> String {',
        '    CURRENT_TEST.with(|cur| cur.borrow().clone().unwrap_or_default())',
        '}',
        '',
        '// The wall-clock budget of one test in milliseconds, read from the',
        '// environment on every run and never at generation time, so one',
        '// generated tree serves every budget. A value that is absent,',
        '// unparsable, or not positive falls back to 5000. The runner carries',
        '// no timer of its own: it reports the test a harness stopped, so this',
        '// check is the only timeout a body that returned late is caught by.',
        'fn timeout_budget_ms() -> u128 {',
        '    let parsed = std::env::var("BORING_TEST_TIMEOUT_MS")',
        '        .ok()',
        '        .and_then(|raw| raw.trim().parse::<u128>().ok());',
        '    match parsed {',
        '        Some(value) if value > 0 => value,',
        '        _ => 5000,',
        '    }',
        '}',
        '',
        '// A test this target excludes (feature spec 19): the entry does not
// run the body and writes the not-applicable record instead, so the
// id stays in the cross-target set.
pub fn record_not_applicable(id: &str, name: &str) {
    record_result(id, name, "not_applicable", None);
}

pub fn run<F: FnOnce()>(id: &str, name: &str, body: F) {',
        '    CURRENT_TEST.with(|cur| {',
        '        *cur.borrow_mut() = Some(id.to_string());',
        '    });',
        '    let budget_ms = timeout_budget_ms();',
        '    let started_at = std::time::Instant::now();',
        '    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body));',
        '    CURRENT_TEST.with(|cur| {',
        '        *cur.borrow_mut() = None;',
        '    });',
        '    match result {',
        '        Ok(_) => {',
        '            if started_at.elapsed().as_millis() >= budget_ms {',
        '                // A body that returned at or past the budget raises',
        '                // through the same path as a failed assertion: the fail',
        '                // line carries the timeout message and the raise travels',
        '                // on, so the runner reports the test as failed too.',
        '                let msg = format!("this test timed out after {}ms", budget_ms);',
        '                record_result(id, name, "fail", Some(&msg));',
        '                std::panic::resume_unwind(Box::new(msg));',
        '            }',
        '            record_result(id, name, "pass", None);',
        '        }',
        '        Err(err) => {',
        '            let msg = if let Some(s) = err.downcast_ref::<String>() {',
        '                s.clone()',
        '            } else if let Some(s) = err.downcast_ref::<&str>() {',
        '                s.to_string()',
        '            } else {',
        '                "test panicked".to_string()',
        '            };',
        '            record_result(id, name, "fail", Some(&msg));',
        '            std::panic::resume_unwind(err);',
        '        }',
        '    }',
        '}',
        '',
        'fn record_result(id: &str, name: &str, verdict: &str, message: Option<&str>) {',
        '    // The resident builds the record line; this module only writes it.',
        '    let json_line = if verdict == "not_applicable" {',
        '        crate::runtime::test_core::TestCore::test_core_not_applicable_line(crate::runtime::u_string::UString::from(id).as_ustr(), crate::runtime::u_string::UString::from(name).as_ustr())',
        '    } else {',
        '        crate::runtime::test_core::TestCore::test_core_result_line(',
        '            crate::runtime::u_string::UString::from(id).as_ustr(),',
        '            crate::runtime::u_string::UString::from(name).as_ustr(),',
        '            verdict == "fail",',
        '            crate::runtime::u_string::UString::from(message.unwrap_or("")).as_ustr(),',
        '        )',
        '    };',
        '    let file_path = std::env::var("BORING_TEST_RESULTS").unwrap_or_else(|_| "out/test-results/rust.jsonl".to_string());',
        '    if let Some(parent) = std::path::Path::new(&file_path).parent() {',
        '        let _ = std::fs::create_dir_all(parent);',
        '    }',
        '    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&file_path) {',
        '        let _ = file.write_all(&json_line.as_bytes());',
        '    }',
        '}',
    ].join("\n");

    /**
        Business ABI adapters appended to the compiled runtime.UString class
        in u_string.rs
        (docs/specs/stdlib/10-unicode-string-access.md). Business modules
        render haxe Int as u32 while the resident class renders i32, and
        Null and Array results have no call-site cast machinery, so the
        adapters cast once here. substring, substr, and the unit-to-byte
        helper keep their P3 contract: the UTF-16 unit bounds of the
        haxe substring and substr members lower into them directly.
    **/
    public static final USTRING_ABI_SOURCE = '
// Business ABI adapters over the resident UString class: Int arguments
// arrive unsigned (u32) and results return u32; the class works in i32.
// slice and substring keep i32 bounds because negative bounds are part
// of their clamping contract. The class lives in this same module, so
// the adapters name it directly without an import.
pub fn count(s: &str) -> u32 {
    u32::try_from(UString::u_string_count(s)).unwrap_or(0)
}

// The String.length member counts UTF-16 code units on every target
// (stdlib/15). The storage here is UTF-8, so a walk over chars() counts
// scalar values and gives one count for a surrogate pair; encode_utf16
// yields the units the member reports.
pub fn unit_count(s: &str) -> u32 {
    u32::try_from(s.encode_utf16().count()).unwrap_or(0)
}

// The UTF-16 code-unit vector of a string, built once. Per-character
// loops that read length and per-index units lower against this vector
// instead of rescanning the UTF-8 source on every access, which turns a
// per-character scan into a quadratic blow-up on large blocks.
pub fn units(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

// The single UTF-16 unit at `index` read from a precomputed unit vector,
// the O(1) form of String.charCodeAt. It answers None past the last unit,
// matching the unit_at read it replaces, so the call-site unwrap (or the
// nullable Option context) rides the same machinery unchanged.
pub fn unit_at_from(units: &[u16], index: u32) -> Option<u32> {
    units.get(usize::try_from(index).unwrap_or(0)).map(|u| u32::from(*u))
}

// The single UTF-16 unit at `index` as an owned one-unit String, the
// O(1) form of String.charAt; an out-of-range index yields the empty
// string, matching charAt past the end.
pub fn char_at_from(units: &[u16], index: u32) -> String {
    let i = usize::try_from(index).unwrap_or(0);
    if i < units.len() {
        String::from_utf16_lossy(&units[i..i + 1])
    } else {
        String::new()
    }
}

// The code-point read that std.UString.at lowers to: the index counts
// characters and the value is one code point, so a surrogate pair
// occupies one address and yields its combined code point.
pub fn at(s: &str, index: u32) -> Option<u32> {
    let mut remaining = index;
    for c in s.chars() {
        if remaining == 0 {
            return Some(u32::from(c));
        }
        remaining -= 1;
    }
    None
}

// The unit read that String.charCodeAt lowers to (stdlib spec 15): the
// index counts UTF-16 code units, so each half of a surrogate pair
// carries its own address and the value is the unit, never the combined
// code point. An index past the last unit answers None, never a panic.
pub fn unit_at(s: &str, index: u32) -> Option<u32> {
    let mut remaining = index;
    for unit in s.encode_utf16() {
        if remaining == 0 {
            return Some(u32::from(unit));
        }
        remaining -= 1;
    }
    None
}

pub fn split(s: &str, separator: &str) -> Vec<String> {
    let source: Vec<u16> = s.encode_utf16().collect();
    let needle: Vec<u16> = separator.encode_utf16().collect();
    if needle.is_empty() {
        let mut out = Vec::new();
        for unit in source {
            out.push(String::from_utf16_lossy(&[unit]));
        }
        return out;
    }
    let mut out = Vec::new();
    let mut start = 0usize;
    let mut cursor = 0usize;
    while cursor + needle.len() <= source.len() {
        if &source[cursor..cursor + needle.len()] == needle {
            out.push(String::from_utf16_lossy(&source[start..cursor]));
            cursor += needle.len();
            start = cursor;
        } else {
            cursor += 1;
        }
    }
    out.push(String::from_utf16_lossy(&source[start..]));
    out
}

pub fn slice(s: &str, from: i32, to: i32) -> String {
    UString::u_string_slice(s, from, to)
}

pub fn to_code_points(s: &str) -> Vec<u32> {
    let mut out = Vec::new();
    for code in UString::u_string_to_code_points(s) {
        out.push(u32::try_from(code).unwrap_or(0));
    }
    out
}

pub fn from_code_point(code: u32) -> String {
    UString::u_string_from_code_point(i32::try_from(code).unwrap_or(0))
}

pub fn from_code_points(codes: &Vec<u32>) -> String {
    let mut inner = Vec::with_capacity(codes.len());
    for index in 0..codes.len() {
        inner.push(i32::try_from(codes[index]).unwrap_or(0));
    }
    UString::u_string_from_code_points(&mut inner)
}

// substring keeps i32 bounds for the same clamping reason as slice:
// negative bounds are part of the haxe substring contract.
pub fn substring(s: &str, from: i32, to: i32) -> String {
    let mut start = if from < 0 { 0u32 } else { u32::try_from(from).unwrap_or(0) };
    let mut end = if to < 0 { 0u32 } else { u32::try_from(to).unwrap_or(0) };
    if start > end {
        let tmp = start;
        start = end;
        end = tmp;
    }
    let byte_start = unit_index(s, start, true);
    let byte_end = unit_index(s, end, false);
    s[byte_start..byte_end].to_string()
}

pub fn substring_from(s: &str, from: i32) -> String {
    let start = if from < 0 { 0u32 } else { u32::try_from(from).unwrap_or(0) };
    s[unit_index(s, start, true)..].to_string()
}

// substr keeps i32 bounds like substring, and it addresses the same
// UTF-16 unit sequence: the position and the length count units, and
// the two unit bounds convert to byte boundaries through unit_index
// before the slice. A negative pos counts from the end of the unit
// sequence per the std contract. A negative len is unspecified in the
// std (std/String.hx), so this runtime returns the empty string,
// matching the JavaScript target, and features/08 rules the shared
// domain to non-negative len values.
pub fn substr(s: &str, pos: i32, len: Option<i32>) -> String {
    match len {
        Some(l) if l < 0 => return String::new(),
        _ => {}
    }
    let units = i64::try_from(s.encode_utf16().count()).unwrap_or(0);
    let start = if pos < 0 {
        let back = i64::from(pos).saturating_neg();
        if units > back { units - back } else { 0 }
    } else {
        if i64::from(pos) > units { units } else { i64::from(pos) }
    };
    let end = match len {
        None => units,
        Some(l) => {
            let raw = start + i64::from(l);
            if raw > units { units } else { raw }
        }
    };
    let byte_start = unit_index(s, u32::try_from(start).unwrap_or(0), true);
    let byte_end = unit_index(s, u32::try_from(end).unwrap_or(0), false);
    s[byte_start..byte_end].to_string()
}

// Haxe Std.parseFloat lowers here. The token must match the full decimal
// grammar after trimming the fixed whitespace set; any partial or
// nonfinite spelling yields NaN.
pub fn parse_f64(s: &str) -> f64 {
    let t = trim_fixed(s);
    if !valid_decimal_token(t.as_bytes()) {
        return f64::NAN;
    }
    t.parse::<f64>().unwrap_or(f64::NAN)
}

// Binary32 edge of the same lowering for the float-precision=f32 lane.
pub fn parse_f32(s: &str) -> f32 {
    let t = trim_fixed(s);
    if !valid_decimal_token(t.as_bytes()) {
        return f32::NAN;
    }
    t.parse::<f32>().unwrap_or(f32::NAN)
}

// Haxe Std.parseInt lowers here: an optional sign, an optional 0x or 0X
// prefix, digits of the implied radix, and the i32 range gate; every
// other shape yields None.
pub fn parse_i32(s: &str) -> Option<i32> {
    let t = trim_fixed(s);
    let b = t.as_bytes();
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
    let magnitude = match u32::from_str_radix(&t[start..], radix) {
        Ok(value) => value,
        Err(_) => return None,
    };
    let signed = if negative { -i64::from(magnitude) } else { i64::from(magnitude) };
    i32::try_from(signed).ok()
}

// The whitespace set of the Haxe scanners: space plus the ASCII control
// range 9 through 13. Unicode whitespace beyond it stays in the token and
// fails validation.
fn trim_fixed(s: &str) -> &str {
    s.trim_matches(|c: char| c == \' \' || matches!(c, \'\\t\'..=\'\\r\'))
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

// UTF-16 unit boundary to byte boundary, the index space of the haxe
// substring and substr contracts. A bound that falls inside a
// surrogate pair moves to the far side: `from` advances past the pair,
// `to` retreats before it, so a Rust slice never splits a pair; the
// subset only produces code-point-aligned bounds, where every target
// agrees.
fn unit_index(s: &str, unit: u32, round_up: bool) -> usize {
    let mut u: u32 = 0;
    for (b, c) in s.char_indices() {
        if u >= unit {
            return b;
        }
        let w = u32::try_from(c.len_utf16()).unwrap_or(0);
        if u + w > unit {
            return if round_up { b + c.len_utf8() } else { b };
        }
        u += w;
    }
    s.len()
}

// String.indexOf with a start position (stdlib spec 15): the start and
// the returned index both count UTF-16 code units, matching the tiqian
// ABI. A negative start is treated as 0 (Haxe/JS semantics); a start
// past the last unit, or one that lands mid-surrogate (rounded up to
// the next char), yields -1. The match index converts back to units so
// the caller sees the same index space as the no-start find() form.
pub fn find_from(s: &str, needle: &str, start: i32) -> i32 {
    let start_unit = if start < 0 { 0u32 } else { u32::try_from(start).unwrap_or(u32::MAX) };
    let byte_start = unit_index(s, start_unit, true);
    let rest = &s[byte_start..];
    match rest.find(needle) {
        Some(byte_rel) => {
            let unit = byte_to_unit(s, byte_start + byte_rel);
            i32::try_from(unit).unwrap_or(-1)
        }
        None => -1,
    }
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
';

    /**
        UString and UStr newtype definitions for the Rust target's unit-based
        string storage (docs/specs/stdlib/10-unicode-string-access.md).
        UString is the owned form, UStr the borrowed slice, matching
        String/&str. Both Deref to [u16], so Index, len and slicing come
        from the slice. This replaces the compiled runtime.UString unit
        struct: the resident walk is folded into the ABI adapters below.
    **/
    public static final USTRING_TYPE_SOURCE = '
// Haxe String storage: owned UTF-16 code units, the Rust target\'s
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

    /// The UTF-16 code units as an iterator (String.encodeUtf16). Mirrors
    /// the UString inherent method so `&UStr` receivers resolve too.
    pub fn encode_utf16(&self) -> std::slice::Iter<u16> {
        self.0.iter()
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
    pub fn encode_utf16(&self) -> std::slice::Iter<u16> {
        self.0.iter()
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
';

    /**
        Business ABI adapters over UString/UStr: Int arguments arrive
        unsigned (u32) and results return u32. This is the unit-based
        rewrite of the original u_string adapters. slice, substring,
        and substr keep i32 bounds because negative bounds are part of
        their clamping contract.
    **/
    public static final USTRING_ABI_SOURCE_NEW = '
// Business ABI adapters: Int arguments arrive unsigned (u32), results
// return u32. slice, substring, and substr keep i32 bounds because
// negative bounds are part of their clamping contract.

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
// negative bounds are part of the haxe substring contract.
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

// substr: pos and len count units per the std contract.
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
    s.trim_matches(|c: char| c == \' \' || matches!(c, \'\\t\'..=\'\\r\'))
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
    for i in 0..=rest.len().saturating_sub(n.len()) {
        if &rest[i..i + n.len()] == n {
            return i32::try_from(u32::try_from(begin + i).unwrap_or(0)).unwrap_or(-1);
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
';

    /**
        Business ABI adapter appended to the compiled runtime.Graphemes
        class in graphemes.rs
        (docs/specs/stdlib/11-grapheme-clusters.md). The boundary vector
        of boundaries crosses whole from the resident i32 domain into the
        business u32 domain; Array results have no call-site cast
        machinery, so the adapter casts each element once here, the
        pattern of USTRING_ABI_SOURCE above.
    **/
    public static final GRAPHEMES_ABI_SOURCE = '
// Business ABI adapter over the resident Graphemes class: the boundary
// vector crosses whole from the resident i32 domain into the business
// u32 domain, element by element. Every scalar operation keeps its
// call-site cast and does not pass through here.
pub fn boundaries(s: &str) -> Vec<u32> {
    let mut out = Vec::new();
    for unit in Graphemes::graphemes_boundaries(s) {
        out.push(u32::try_from(unit).unwrap_or(0));
    }
    out
}
';
}
#end
