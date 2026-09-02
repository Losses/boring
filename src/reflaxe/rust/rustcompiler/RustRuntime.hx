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

    // Binary32 variants of the two value edges: the same 8 wire bytes
    // decode to the f64 value, then round once to the module real; the
    // reverse widens losslessly before the bit conversion. Only the
    // float-precision=f32 lane references them (feature spec 23).
    pub fn i64_to_f32(low: u32, high: u32) -> f32 {
        Self::i64_to_double(low, high) as f32
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
		'fn record_result(id: &str, name: &str, verdict: &str, message: Option<&str>) {',
		'    // The resident builds the record line; this module only writes it.',
		'    let json_line = crate::runtime::test_core::TestCore::result_line(',
		'        id,',
		'        name,',
		'        verdict == "fail",',
		'        message.unwrap_or(""),',
		'    );',
		'    let file_path = std::env::var("BORING_TEST_RESULTS").unwrap_or_else(|_| "out/test-results/rust.jsonl".to_string());',
		'    if let Some(parent) = std::path::Path::new(&file_path).parent() {',
		'        let _ = std::fs::create_dir_all(parent);',
		'    }',
		'    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(&file_path) {',
		'        let _ = file.write_all(json_line.as_bytes());',
		'    }',
		'}',
	].join("\n");



	/**
		Business ABI adapters appended to the compiled runtime.UString class
		in u_string.rs
		(docs/specs/stdlib/10-unicode-string-access.md). Business modules
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
    let mut remaining = index;
    for c in s.chars() {
        if remaining == 0 {
            return Some(c as u32);
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
        if source[cursor..cursor + needle.len()] == needle[..] {
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
    for unit in Graphemes::boundaries(s) {
        out.push(unit as u32);
    }
    out
}
';
}
#end
