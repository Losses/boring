package rustcompiler;

#if (macro || reflaxe_runtime)
/**
	Headerless runtime shim sources for the standard library, emitted on
	demand under the configured runtime package.
**/
class RustRuntime {
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

	public static final TEST_SOURCE = [
		'use std::cell::RefCell;',
		'use std::fs::OpenOptions;',
		'use std::io::Write;',
		'',
		'thread_local! {',
		'    static CURRENT_TEST: RefCell<Option<String>> = RefCell::new(None);',
		'}',
		'',
		'fn current_test_id() -> String {',
		'    CURRENT_TEST.with(|cur| cur.borrow().clone().unwrap_or_default())',
		'}',
		'',
		'pub fn run<F: FnOnce()>(id: &str, name: &str, body: F) {',
		'    CURRENT_TEST.with(|cur| {',
		'        *cur.borrow_mut() = Some(id.to_string());',
		'    });',
		'    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(body));',
		'    CURRENT_TEST.with(|cur| {',
		'        *cur.borrow_mut() = None;',
		'    });',
		'    match result {',
		'        Ok(_) => {',
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
		'pub fn ok(condition: bool, message: Option<&str>) {',
		'    if !condition {',
		'        let cur_id = current_test_id();',
		'        let canonical = format_canonical_message(&cur_id, message, None, None, false);',
		'        panic!("{}", canonical);',
		'    }',
		'}',
		'',
		'pub fn fail(message: &str) {',
		'    let cur_id = current_test_id();',
		'    let canonical = format_canonical_message(&cur_id, Some(message), None, None, false);',
		'    panic!("{}", canonical);',
		'}',
		'',
		'pub fn equals_bool(expected: bool, actual: bool, message: Option<&str>) {',
		'    if expected != actual {',
		'        let cur_id = current_test_id();',
		'        let canonical = format_canonical_message(&cur_id, message, Some(&expected.to_string()), Some(&actual.to_string()), true);',
		'        panic!("{}", canonical);',
		'    }',
		'}',
		'',
		'pub fn equals_i32(expected: i32, actual: i32, message: Option<&str>) {',
		'    if expected != actual {',
		'        let cur_id = current_test_id();',
		'        let canonical = format_canonical_message(&cur_id, message, Some(&expected.to_string()), Some(&actual.to_string()), true);',
		'        panic!("{}", canonical);',
		'    }',
		'}',
		'',
		'pub fn equals_u32(expected: u32, actual: u32, message: Option<&str>) {',
		'    if expected != actual {',
		'        let cur_id = current_test_id();',
		'        let canonical = format_canonical_message(&cur_id, message, Some(&expected.to_string()), Some(&actual.to_string()), true);',
		'        panic!("{}", canonical);',
		'    }',
		'}',
		'',
		'pub fn equals_f64(expected: f64, actual: f64, message: Option<&str>) {',
		'    // IEEE equality: NaN != NaN',
		'    if expected != actual {',
		'        let cur_id = current_test_id();',
		'        let canonical = format_canonical_message(&cur_id, message, Some(&format_float(expected)), Some(&format_float(actual)), true);',
		'        panic!("{}", canonical);',
		'    }',
		'}',
		'',
		'pub fn equals_str(expected: &str, actual: &str, message: Option<&str>) {',
		'    if expected != actual {',
		'        let cur_id = current_test_id();',
		'        let canonical = format_canonical_message(&cur_id, message, Some(&format_string(expected)), Some(&format_string(actual)), true);',
		'        panic!("{}", canonical);',
		'    }',
		'}',
		'',
		'pub fn report_failure(message: Option<&str>, expected_str: &str, actual_str: &str) {',
		'    let cur_id = current_test_id();',
		'    let canonical = format_canonical_message(&cur_id, message, Some(expected_str), Some(actual_str), true);',
		'    panic!("{}", canonical);',
		'}',
		'',
		'pub fn format_float(v: f64) -> String {',
		'    if v.is_nan() { "NaN".to_string() }',
		'    else if v == f64::INFINITY { "Infinity".to_string() }',
		'    else if v == f64::NEG_INFINITY { "-Infinity".to_string() }',
		'    else if v == 0.0 || v == -0.0 { "0".to_string() }',
		'    else { v.to_string() }',
		'}',
		'',
		'pub fn format_string(s: &str) -> String {',
		'    format!("\\\"{}\\\"", escape_json(s))',
		'}',
		'',
		'pub fn format_bytes(b: &[u8]) -> String {',
		'    let mut out = String::new();',
		'    for byte in b { out.push_str(&format!("{:02x}", byte)); }',
		'    out',
		'}',
		'',
		'pub fn escape_json(s: &str) -> String {',
		'    let mut buf = String::new();',
		'    for c in s.chars() {',
		'        let code = c as u32;',
		'        if code == 0x22 { buf.push_str("\\\\\\\""); }',
		'        else if code == 0x5c { buf.push_str("\\\\\\\\"); }',
		'        else if code == 0x0a { buf.push_str("\\\\n"); }',
		'        else if code == 0x0d { buf.push_str("\\\\r"); }',
		'        else if code == 0x09 { buf.push_str("\\\\t"); }',
		'        else if code < 0x20 { buf.push_str(&format!("\\\\u{:04x}", code)); }',
		'        else { buf.push(c); }',
		'    }',
		'    buf',
		'}',
		'',
		'pub fn format_canonical_message(id: &str, message: Option<&str>, expected_str: Option<&str>, actual_str: Option<&str>, is_equals: bool) -> String {',
		'    let mut lines = Vec::new();',
		'    lines.push(format!("test failed: {}", id));',
		'    if let Some(msg) = message {',
		'        if !msg.is_empty() {',
		'            lines.push(format!("  message: {}", msg));',
		'        }',
		'    }',
		'    if is_equals {',
		'        lines.push(format!("  expected: {}", expected_str.unwrap_or("")));',
		'        lines.push(format!("  actual:   {}", actual_str.unwrap_or("")));',
		'    }',
		'    lines.join("\\n")',
		'}',
		'',
		'fn record_result(id: &str, name: &str, verdict: &str, message: Option<&str>) {',
		'    let file_path = std::env::var("BORING_TEST_RESULTS").unwrap_or_else(|_| "out/test-results/rust.jsonl".to_string());',
		'    let json_line = if verdict == "pass" {',
		'        format!("{{\\\"id\\\":\\\"{}\\\",\\\"name\\\":\\\"{}\\\",\\\"verdict\\\":\\\"pass\\\"}}\\n", escape_json(id), escape_json(name))',
		'    } else {',
		'        format!("{{\\\"id\\\":\\\"{}\\\",\\\"name\\\":\\\"{}\\\",\\\"verdict\\\":\\\"fail\\\",\\\"message\\\":\\\"{}\\\"}}\\n", escape_json(id), escape_json(name), escape_json(message.unwrap_or("")))',
		'    };',
		'    if let Some(parent) = std::path::Path::new(&file_path).parent() {',
		'        let _ = std::fs::create_dir_all(parent);',
		'    }',
		'    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&file_path) {',
		'        let _ = file.write_all(json_line.as_bytes());',
		'    }',
		'}'
	].join("\n");

	public static final SORTED_MAP_SOURCE = '
#[derive(Debug, Clone, PartialEq)]
pub struct SortedMap<V> {
    keys: Vec<u32>,
    values: Vec<V>,
}

pub struct SortedMapBuilder<V> {
    entries: Vec<(u32, usize, V)>,
}

impl<V: Clone> SortedMap<V> {
    pub fn builder() -> SortedMapBuilder<V> {
        SortedMapBuilder::new()
    }

    pub fn get(&self, key: u32) -> Option<V> {
        match self.keys.binary_search(&key) {
            Ok(idx) => Some(self.values[idx].clone()),
            Err(_) => None,
        }
    }

    pub fn has(&self, key: u32) -> bool {
        self.keys.binary_search(&key).is_ok()
    }

    pub fn size(&self) -> u32 {
        self.keys.len() as u32
    }

    pub fn key_at(&self, index: u32) -> u32 {
        self.keys[index as usize]
    }

    pub fn value_at(&self, index: u32) -> V {
        self.values[index as usize].clone()
    }
}

impl<V: Clone> SortedMapBuilder<V> {
    pub fn new() -> Self {
        Self { entries: Vec::new() }
    }

    pub fn put(&mut self, key: u32, value: impl Into<V>) {
        let idx = self.entries.len();
        self.entries.push((key, idx, value.into()));
    }

    pub fn get(&self, key: u32) -> Option<V> {
        for entry in self.entries.iter().rev() {
            if entry.0 == key {
                return Some(entry.2.clone());
            }
        }
        None
    }

    pub fn build(mut self) -> SortedMap<V> {
        if self.entries.is_empty() {
            return SortedMap { keys: Vec::new(), values: Vec::new() };
        }
        self.entries.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.cmp(&b.1)));

        let mut keys = Vec::new();
        let mut values = Vec::new();

        let mut i = 0;
        while i < self.entries.len() {
            let mut j = i;
            while j + 1 < self.entries.len() && self.entries[j + 1].0 == self.entries[i].0 {
                j += 1;
            }
            keys.push(self.entries[j].0);
            values.push(self.entries[j].2.clone());
            i = j + 1;
        }

        SortedMap { keys, values }
    }
}

pub fn compare_utf16_code_units(a: &str, b: &str) -> std::cmp::Ordering {
    let ba = a.as_bytes();
    let bb = b.as_bytes();
    let min_len = ba.len().min(bb.len());
    for i in 0..min_len {
        let b1 = ba[i];
        let b2 = bb[i];
        if b1 != b2 {
            let is_a_astral = (0xF0..=0xF4).contains(&b1);
            let is_b_astral = (0xF0..=0xF4).contains(&b2);
            let is_a_high_bmp = (0xEE..=0xEF).contains(&b1);
            let is_b_high_bmp = (0xEE..=0xEF).contains(&b2);
            if is_a_astral && is_b_high_bmp {
                return b2.cmp(&b1);
            }
            if is_a_high_bmp && is_b_astral {
                return b2.cmp(&b1);
            }
            return b1.cmp(&b2);
        }
    }
    ba.len().cmp(&bb.len())
}

#[derive(Debug, Clone, PartialEq)]
pub struct SortedMapStr<V> {
    keys: Vec<String>,
    values: Vec<V>,
}

pub struct SortedMapStrBuilder<V> {
    entries: Vec<(String, usize, V)>,
}

impl<V: Clone> SortedMapStr<V> {
    pub fn builder() -> SortedMapStrBuilder<V> {
        SortedMapStrBuilder::new()
    }

    pub fn get(&self, key: &str) -> Option<V> {
        match self.keys.binary_search_by(|probe| compare_utf16_code_units(probe.as_str(), key)) {
            Ok(idx) => Some(self.values[idx].clone()),
            Err(_) => None,
        }
    }

    pub fn has(&self, key: &str) -> bool {
        self.keys.binary_search_by(|probe| compare_utf16_code_units(probe.as_str(), key)).is_ok()
    }

    pub fn size(&self) -> u32 {
        self.keys.len() as u32
    }

    pub fn key_at(&self, index: u32) -> String {
        self.keys[index as usize].clone()
    }

    pub fn value_at(&self, index: u32) -> V {
        self.values[index as usize].clone()
    }
}

impl<V: Clone> SortedMapStrBuilder<V> {
    pub fn new() -> Self {
        Self { entries: Vec::new() }
    }

    pub fn put(&mut self, key: impl Into<String>, value: V) {
        let idx = self.entries.len();
        self.entries.push((key.into(), idx, value));
    }

    pub fn get(&self, key: &str) -> Option<V> {
        for entry in self.entries.iter().rev() {
            if compare_utf16_code_units(entry.0.as_str(), key) == std::cmp::Ordering::Equal {
                return Some(entry.2.clone());
            }
        }
        None
    }

    pub fn build(mut self) -> SortedMapStr<V> {
        if self.entries.is_empty() {
            return SortedMapStr { keys: Vec::new(), values: Vec::new() };
        }
        self.entries.sort_by(|a, b| {
            let cmp = compare_utf16_code_units(a.0.as_str(), b.0.as_str());
            if cmp != std::cmp::Ordering::Equal {
                cmp
            } else {
                a.1.cmp(&b.1)
            }
        });

        let mut keys = Vec::new();
        let mut values = Vec::new();

        let mut i = 0;
        while i < self.entries.len() {
            let mut j = i;
            while j + 1 < self.entries.len() && compare_utf16_code_units(self.entries[j + 1].0.as_str(), self.entries[i].0.as_str()) == std::cmp::Ordering::Equal {
                j += 1;
            }
            keys.push(self.entries[j].0.clone());
            values.push(self.entries[j].2.clone());
            i = j + 1;
        }

        SortedMapStr { keys, values }
    }
}

#[derive(Debug, Clone)]
pub struct SortedMapByKey<K, V> {
    keys: Vec<K>,
    values: Vec<V>,
    cmp: fn(&K, &K) -> std::cmp::Ordering,
}

impl<K: PartialEq, V: PartialEq> PartialEq for SortedMapByKey<K, V> {
    fn eq(&self, other: &Self) -> bool {
        self.keys == other.keys && self.values == other.values
    }
}

pub struct SortedMapByKeyBuilder<K, V> {
    entries: Vec<(K, usize, V)>,
    cmp: fn(&K, &K) -> std::cmp::Ordering,
}

impl<K: Clone, V: Clone> SortedMapByKey<K, V> {
    pub fn builder(cmp: fn(&K, &K) -> std::cmp::Ordering) -> SortedMapByKeyBuilder<K, V> {
        SortedMapByKeyBuilder::new(cmp)
    }

    pub fn get(&self, key: impl std::borrow::Borrow<K>) -> Option<V> {
        let k = key.borrow();
        match self.keys.binary_search_by(|probe| (self.cmp)(probe, k)) {
            Ok(idx) => Some(self.values[idx].clone()),
            Err(_) => None,
        }
    }

    pub fn has(&self, key: impl std::borrow::Borrow<K>) -> bool {
        let k = key.borrow();
        self.keys.binary_search_by(|probe| (self.cmp)(probe, k)).is_ok()
    }

    pub fn size(&self) -> u32 {
        self.keys.len() as u32
    }

    pub fn key_at(&self, index: u32) -> K {
        self.keys[index as usize].clone()
    }

    pub fn value_at(&self, index: u32) -> V {
        self.values[index as usize].clone()
    }
}

impl<K: Clone, V: Clone> SortedMapByKeyBuilder<K, V> {
    pub fn new(cmp: fn(&K, &K) -> std::cmp::Ordering) -> Self {
        Self { entries: Vec::new(), cmp }
    }

    pub fn put(&mut self, key: K, value: V) {
        let idx = self.entries.len();
        self.entries.push((key, idx, value));
    }

    pub fn get(&self, key: impl std::borrow::Borrow<K>) -> Option<V> {
        let k = key.borrow();
        for entry in self.entries.iter().rev() {
            if (self.cmp)(&entry.0, k) == std::cmp::Ordering::Equal {
                return Some(entry.2.clone());
            }
        }
        None
    }

    pub fn build(mut self) -> SortedMapByKey<K, V> {
        if self.entries.is_empty() {
            return SortedMapByKey { keys: Vec::new(), values: Vec::new(), cmp: self.cmp };
        }
        let cmp_fn = self.cmp;
        self.entries.sort_by(|a, b| {
            let r = cmp_fn(&a.0, &b.0);
            if r != std::cmp::Ordering::Equal {
                r
            } else {
                a.1.cmp(&b.1)
            }
        });

        let mut keys = Vec::new();
        let mut values = Vec::new();

        let mut i = 0;
        while i < self.entries.len() {
            let mut j = i;
            while j + 1 < self.entries.len() && cmp_fn(&self.entries[j + 1].0, &self.entries[i].0) == std::cmp::Ordering::Equal {
                j += 1;
            }
            keys.push(self.entries[j].0.clone());
            values.push(self.entries[j].2.clone());
            i = j + 1;
        }

        SortedMapByKey { keys, values, cmp: self.cmp }
    }
}
';

	public static final SORTED_SET_SOURCE = '
use crate::runtime::sorted_map::compare_utf16_code_units;

#[derive(Debug, Clone, PartialEq)]
pub struct SortedSet {
    keys: Vec<u32>,
}

pub struct SortedSetBuilder {
    keys: Vec<u32>,
}

impl SortedSet {
    pub fn builder() -> SortedSetBuilder {
        SortedSetBuilder::new()
    }

    pub fn has(&self, key: u32) -> bool {
        self.keys.binary_search(&key).is_ok()
    }

    pub fn size(&self) -> u32 {
        self.keys.len() as u32
    }

    pub fn at(&self, index: u32) -> u32 {
        self.keys[index as usize]
    }
}

impl SortedSetBuilder {
    pub fn new() -> Self {
        Self { keys: Vec::new() }
    }

    pub fn put(&mut self, key: u32) {
        self.keys.push(key);
    }

    pub fn build(mut self) -> SortedSet {
        if self.keys.is_empty() {
            return SortedSet { keys: Vec::new() };
        }
        self.keys.sort();
        self.keys.dedup();
        SortedSet { keys: self.keys }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SortedSetStr {
    keys: Vec<String>,
}

pub struct SortedSetStrBuilder {
    keys: Vec<String>,
}

impl SortedSetStr {
    pub fn builder() -> SortedSetStrBuilder {
        SortedSetStrBuilder::new()
    }

    pub fn has(&self, key: &str) -> bool {
        self.keys.binary_search_by(|probe| compare_utf16_code_units(probe.as_str(), key)).is_ok()
    }

    pub fn size(&self) -> u32 {
        self.keys.len() as u32
    }

    pub fn at(&self, index: u32) -> String {
        self.keys[index as usize].clone()
    }
}

impl SortedSetStrBuilder {
    pub fn new() -> Self {
        Self { keys: Vec::new() }
    }

    pub fn put(&mut self, key: impl Into<String>) {
        self.keys.push(key.into());
    }

    pub fn build(mut self) -> SortedSetStr {
        if self.keys.is_empty() {
            return SortedSetStr { keys: Vec::new() };
        }
        self.keys.sort_by(|a, b| compare_utf16_code_units(a.as_str(), b.as_str()));
        self.keys.dedup_by(|a, b| compare_utf16_code_units(a.as_str(), b.as_str()) == std::cmp::Ordering::Equal);
        SortedSetStr { keys: self.keys }
    }
}

#[derive(Debug, Clone)]
pub struct SortedSetByKey<K> {
    keys: Vec<K>,
    cmp: fn(&K, &K) -> std::cmp::Ordering,
}

impl<K: PartialEq> PartialEq for SortedSetByKey<K> {
    fn eq(&self, other: &Self) -> bool {
        self.keys == other.keys
    }
}

pub struct SortedSetByKeyBuilder<K> {
    keys: Vec<K>,
    cmp: fn(&K, &K) -> std::cmp::Ordering,
}

impl<K: Clone> SortedSetByKey<K> {
    pub fn builder(cmp: fn(&K, &K) -> std::cmp::Ordering) -> SortedSetByKeyBuilder<K> {
        SortedSetByKeyBuilder::new(cmp)
    }

    pub fn has(&self, key: impl std::borrow::Borrow<K>) -> bool {
        let k = key.borrow();
        self.keys.binary_search_by(|probe| (self.cmp)(probe, k)).is_ok()
    }

    pub fn size(&self) -> u32 {
        self.keys.len() as u32
    }

    pub fn at(&self, index: u32) -> K {
        self.keys[index as usize].clone()
    }
}

impl<K: Clone> SortedSetByKeyBuilder<K> {
    pub fn new(cmp: fn(&K, &K) -> std::cmp::Ordering) -> Self {
        Self { keys: Vec::new(), cmp }
    }

    pub fn put(&mut self, key: K) {
        self.keys.push(key);
    }

    pub fn build(mut self) -> SortedSetByKey<K> {
        if self.keys.is_empty() {
            return SortedSetByKey { keys: Vec::new(), cmp: self.cmp };
        }
        let cmp_fn = self.cmp;
        self.keys.sort_by(|a, b| cmp_fn(a, b));
        self.keys.dedup_by(|a, b| cmp_fn(a, b) == std::cmp::Ordering::Equal);
        SortedSetByKey { keys: self.keys, cmp: self.cmp }
    }
}
';

	/**
		Business ABI adapters appended to the compiled runtime.UString class
		in u_string.rs (docs/specs/stdlib/10-unicode-string-access.md,
		docs/plans/2026-08-28-runtime-unification.md P5). Business modules
		render haxe Int as u32 while the resident class renders i32, and
		Null and Array results have no call-site cast machinery, so the
		adapters cast once here. substring and its unit-to-byte helpers
		keep their P3 contract: the UTF-16 unit bounds of the haxe
		substring member lower into them directly.
	**/
	public static final USTRING_ABI_SOURCE = '
// Business ABI adapters over the resident UString class: Int arguments
// arrive as u32 and results return u32; the class works in i32. slice and
// substring keep i32 bounds because negative bounds are part of their
// clamping contract. The class lives in this same module, so the
// adapters name it directly without an import.
pub fn count(s: &str) -> u32 {
    UString::count(s) as u32
}

pub fn at(s: &str, index: u32) -> Option<u32> {
    match UString::at(s, index as i32) {
        Some(code) => Some(code as u32),
        None => None,
    }
}

pub fn slice(s: &str, from: i32, to: i32) -> String {
    UString::slice(s, from, to)
}

pub fn to_code_points(s: &str) -> Vec<u32> {
    let mut out = Vec::new();
    for code in UString::to_code_points(s) {
        out.push(code as u32);
    }
    out
}

pub fn from_code_point(code: u32) -> String {
    UString::from_code_point(code as i32)
}

pub fn from_code_points(codes: &mut Vec<u32>) -> String {
    let mut inner = Vec::with_capacity(codes.len());
    for index in 0..codes.len() {
        inner.push(codes[index] as i32);
    }
    UString::from_code_points(&mut inner)
}

// substring keeps i32 bounds for the same clamping reason as slice:
// negative bounds are part of the haxe substring contract.
pub fn substring(s: &str, from: i32, to: i32) -> String {
    let mut start = if from < 0 { 0u32 } else { from as u32 };
    let mut end = if to < 0 { 0u32 } else { to as u32 };
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
    let start = if from < 0 { 0u32 } else { from as u32 };
    s[unit_index(s, start, true)..].to_string()
}

// UTF-16 unit boundary to byte boundary, the index space of the haxe
// substring contract. A bound that falls inside a surrogate pair moves
// to the far side: `from` advances past the pair, `to` retreats before
// it, so a Rust slice never splits a pair; the subset only produces
// code-point-aligned bounds, where every target agrees.
fn unit_index(s: &str, unit: u32, round_up: bool) -> usize {
    let mut u: u32 = 0;
    for (b, c) in s.char_indices() {
        if u >= unit {
            return b;
        }
        let w = c.len_utf16() as u32;
        if u + w > unit {
            return if round_up { b + c.len_utf8() } else { b };
        }
        u += w;
    }
    s.len()
}
';
}
#end
