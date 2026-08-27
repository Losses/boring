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
}
#end
