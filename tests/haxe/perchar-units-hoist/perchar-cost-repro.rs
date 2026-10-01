// Self-contained measurement harness for the per-character `units` defect
// (boring task t-mukem10i-n8ll). The two functions under test are copied
// VERBATIM from a generated Tiqian tree, so the numbers describe the generated
// code, not a rewrite of it: only the hoists are lifted to the caller, which is
// what the fix makes the compiler do.
use std::sync::atomic::{AtomicU64, Ordering};

pub static UNITS_CALLS: AtomicU64 = AtomicU64::new(0);
pub static UNITS_BYTES: AtomicU64 = AtomicU64::new(0);
pub static UNIT_AT_CALLS: AtomicU64 = AtomicU64::new(0);
pub static PRE_UNITS_CALLS: AtomicU64 = AtomicU64::new(0);

pub mod u_string {
    pub fn units(s: &str) -> Vec<u16> {
        super::UNITS_CALLS.fetch_add(1, super::Ordering::Relaxed);
        super::UNITS_BYTES.fetch_add(s.len() as u64, super::Ordering::Relaxed);
        s.encode_utf16().collect()
    }
    pub fn parse_f64(text: &str) -> f64 { text.trim().parse::<f64>().unwrap_or(f64::NAN) }
    pub fn unit_count(s: &str) -> u32 { u32::try_from(s.encode_utf16().count()).unwrap_or(0) }
    pub fn unit_at_from(units: &[u16], index: u32) -> Option<u32> {
        units.get(usize::try_from(index).unwrap_or(0)).map(|u| u32::from(*u))
    }
    pub fn unit_at(s: &str, index: u32) -> Option<u32> {
        let mut remaining = index;
        for unit in s.encode_utf16() { if remaining == 0 { return Some(u32::from(unit)); } remaining -= 1; }
        None
    }
    pub fn substring(s: &str, start: i32, end: i32) -> String {
        let units: Vec<u16> = s.encode_utf16().collect();
        let a = usize::try_from(start.max(0)).unwrap_or(0).min(units.len());
        let b = usize::try_from(end.max(0)).unwrap_or(0).min(units.len());
        String::from_utf16_lossy(&units[a.min(b)..b])
    }
    pub fn substring_from(s: &str, start: i32) -> String {
        let units: Vec<u16> = s.encode_utf16().collect();
        let a = usize::try_from(start.max(0)).unwrap_or(0).min(units.len());
        String::from_utf16_lossy(&units[a..])
    }
    pub fn escape_text(text: &str) -> String {
        let mut out = String::new();
        for c in text.chars() {
            match c {
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                '\\' => out.push_str("\\\\"),
                '"' => out.push_str("\\\""),
                _ => out.push(c),
            }
        }
        out
    }
    pub fn char_at_from(units: &[u16], index: u32) -> String {
        let i = usize::try_from(index).unwrap_or(0);
        if i < units.len() { String::from_utf16_lossy(&units[i..i + 1]) } else { String::new() }
    }
}

pub struct UnsupportedCharacterFault { pub unit: u32 }
pub mod u_string_escape {}
pub struct TraceFormat;
impl TraceFormat {
    pub fn trace_format_value_bool(value: bool) -> String { if value { "true".into() } else { "false".into() } }
}
impl TraceFormat {
    pub fn trace_format_i(value: u32) -> String { format!("{value}") }
    pub fn trace_format_value_long(value: u32) -> String { format!("{value}") }
    pub fn trace_format_fd(value: f64, digits: i32) -> String { format!("{value:.prec$}", prec = digits.max(0) as usize) }
}

pub mod string_tools {
    pub struct StringTools;
    impl StringTools {
        pub fn string_tools_lpad(s: &str, pad: &str, len: i32) -> String {
            let mut out = s.to_string();
            while (out.chars().count() as i32) < len { out = format!("{pad}{out}"); }
            out
        }
    }
}
use runtime::fp_helper::FPHelper;

pub mod runtime {
    pub mod fp_helper {
        pub struct FPHelper;
        impl FPHelper {
            pub fn float_to_i32(value: f64) -> i32 { value as i32 }
            pub fn format_float(value: f64) -> String {
                if value == value.trunc() && value.abs() < 1e15 {
                    format!("{}", value as i64)
                } else {
                    format!("{value}")
                }
            }
        }
    }
    pub mod int_text {
        pub struct IntText;
        impl IntText {
            pub fn int_text(value: u32) -> String { char::from_u32(value).map(|c| c.to_string()).unwrap_or_default() }
        }
    }
}

use std::fmt::Write;


pub struct TestTraceRender;

impl TestTraceRender {
    const TEST_TRACE_RENDER_MAX_OPERAND_CHARS: u32 = 240;
    const TEST_TRACE_RENDER_HEX: &str = "0123456789abcdef";
    const TEST_TRACE_RENDER_MAX_SIGNIFICANT_DIGITS: u32 = 9;

    pub fn test_trace_render_escape_operand(value: &str) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TestTraceRender::test_trace_render_escape(value).as_str())?);
    }

    pub fn test_trace_render_render_string(value: &str) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_cap(format!("{}{}{}",
            "'",
            TestTraceRender::test_trace_render_escape(value),
            "'"
        ).as_str())?);
    }

    pub fn test_trace_render_render_int(value: u32) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_i(value).as_str())?);
    }

    pub fn test_trace_render_render_long(value: u32) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_value_long(value).as_str())?);
    }

    pub fn test_trace_render_render_float(value: f64) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_fd(value, 6).as_str())?);
    }

    pub fn test_trace_render_float_text(value: f64) -> Result<String, UnsupportedCharacterFault> {
        let negative = value < (0 as f64);
        let v = (value).abs();
        if v == 0 as f64 {
            return Ok(if negative { "-0.0".to_string() } else { "0.0".to_string() });
        }
        let shape = TestTraceRender::test_trace_render_decimal_shape(v)?;
        if shape.is_none() {
            return Ok(format!("{}{}",
            (if negative { "-".to_string() } else { "".to_string() }),
            v
        ));
        }
        let digits = ((shape).as_ref().unwrap().digits).to_string().clone();
        let width = u_string::unit_count(&(digits));
        let position = (shape).as_ref().unwrap().position;
        let target_bits = FPHelper::float_to_i32(v);
        let mut p = 1u32;
        while (i32::from_ne_bytes((p).to_ne_bytes())) <= 9 {
            let exp = u32::wrapping_sub(position, p);
            let base = if i32::from_ne_bytes((p).to_ne_bytes()) >= i32::from_ne_bytes((width).to_ne_bytes()) { u32::wrapping_mul(TestTraceRender::test_trace_render_decimal_int(digits.as_str()), TestTraceRender::test_trace_render_pow10_int(u32::wrapping_sub(p, width))) } else {
TestTraceRender::test_trace_render_decimal_int(u_string::substring(&digits, 0i32, i32::from_ne_bytes((p).to_ne_bytes())).as_str()) };
            let frac = TestTraceRender::test_trace_render_fraction_after(digits.as_str(), p, (shape).as_ref().unwrap().extended);
            let mut best = 4294967295u32;
            let mut best_dist = f64::INFINITY;
            let mut c = u32::wrapping_sub(base, 1);
            while (i32::from_ne_bytes((c).to_ne_bytes())) <= i32::from_ne_bytes((u32::wrapping_add(base, 2)).to_ne_bytes()) {
                if i32::from_ne_bytes((c).to_ne_bytes()) >= 1 {
                    let candidate_text = format!("{}{}{}",
            crate::runtime::int_text::IntText::int_text(c),
            "e",
            crate::runtime::int_text::IntText::int_text(exp)
        );
                    let cand = u_string::parse_f64(&(candidate_text));
                    if FPHelper::float_to_i32(cand) == target_bits {
                        let dist = (format!("{}", (i32::from_ne_bytes((u32::wrapping_sub(c, base)).to_ne_bytes()))).parse::<f64>().unwrap_or(0.0) - frac).abs();
                        if dist < (best_dist) || dist == best_dist && u32::from_ne_bytes((i32::from_ne_bytes((c).to_ne_bytes()) % 2i32).to_ne_bytes()) == 0 {
                            best = c;
                            best_dist = dist;
                        }
                    }
                }
                c = u32::wrapping_add(c, 1);
            }
            if best <= 2147483647 {
                return Ok(TestTraceRender::test_trace_render_float_text_render(best, u32::wrapping_sub(position, 1), p, negative)?);
            }
            p = u32::wrapping_add(p, 1);
        }
        return Ok(format!("{}{}",
            (if negative { "-".to_string() } else { "".to_string() }),
            v
        ));
    }

    pub(crate) fn test_trace_render_decimal_int(digits: &str) -> u32 {
    let __units = u_string::units(&digits);
    let __count = u_string::unit_count(&digits);
        let mut value = 0u32;
        let mut index = 0u32;
        let __units1 = u_string::units(&digits);
        let __count1 = u_string::unit_count(&digits);
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count).to_ne_bytes())) {
            value = u32::wrapping_sub(u32::wrapping_add(u32::wrapping_mul(value, 10), u_string::unit_at_from(&__units1, index).unwrap_or(0)), 48);
            index = u32::wrapping_add(index, 1);
        }
        return value;
    }

    pub(crate) fn test_trace_render_pow10_int(exponent: u32) -> u32 {
        let mut value = 1u32;
        for _ in 0..exponent {
            value = u32::wrapping_mul(value, 10);
        }
        return value;
    }

    pub(crate) fn test_trace_render_fraction_after(digits: &str, p: u32, extended: bool) -> f64 {
    let __units2 = u_string::units(&digits);
    let __count2 = u_string::unit_count(&digits);
        if i32::from_ne_bytes((p).to_ne_bytes()) >= i32::from_ne_bytes((__count2).to_ne_bytes()) {
            return 0.0f64;
        }
        let frac = u_string::parse_f64(&(format!("{}{}",
            "0.",
            u_string::substring_from(&digits, i32::from_ne_bytes((p).to_ne_bytes()))
        )));
        if extended && frac == 0.5f64 {
            return 0.75f64;
        }
        return frac;
    }

    pub(crate) fn test_trace_render_decimal_shape(v: f64) -> Result<Option<DecimalShape>, UnsupportedCharacterFault> {
        if !(v).is_finite() {
            return Ok(None);
        }
        let plain = TestTraceRender::test_trace_render_expand_scientific(crate::runtime::fp_helper::FPHelper::format_float(v).as_str(), &u_string::units(crate::runtime::fp_helper::FPHelper::format_float(v).as_str()), u_string::unit_count(crate::runtime::fp_helper::FPHelper::format_float(v).as_str()))?;
        let mut point = u_string::unit_count(&(plain));
        let mut index = 0u32;
        let __units3 = u_string::units(&plain);
        let __count3 = u_string::unit_count(&plain);
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count3).to_ne_bytes())) {
            if u_string::unit_at_from(&__units3, index).as_ref().map_or(false, |v| v == &(46)) {
                point = index;
                break;
            }
            index = u32::wrapping_add(index, 1);
        }
        let all = format!("{}{}",
            u_string::substring(&plain, 0i32, i32::from_ne_bytes((point).to_ne_bytes())),
            u_string::substring_from(&plain, i32::from_ne_bytes((u32::wrapping_add(point, 1)).to_ne_bytes()))
        );
        let mut first = 0u32;
        let __units4 = u_string::units(&all);
        let __count4 = u_string::unit_count(&all);
        while (i32::from_ne_bytes((first).to_ne_bytes())) < (i32::from_ne_bytes((__count4).to_ne_bytes())) && u_string::unit_at_from(&__units4, first).as_ref().map_or(false, |v| v == &(48)) {
            first = u32::wrapping_add(first, 1);
        }
        if first == u_string::unit_count(&(all)) {
            return Ok(None);
        }
        let mut last = u_string::unit_count(&(all));
        while (i32::from_ne_bytes((last).to_ne_bytes())) > (i32::from_ne_bytes((u32::wrapping_add(first, 1)).to_ne_bytes())) && u_string::unit_at(&all, u32::wrapping_sub(last, 1)).as_ref().map_or(false, |v| v == &(48)) {
            last = u32::wrapping_sub(last, 1);
        }
        let mut digits = String::new();
        let mut extended = false;
        let mut cursor = first;
        while (i32::from_ne_bytes((cursor).to_ne_bytes())) < (i32::from_ne_bytes((last).to_ne_bytes())) {
            if i32::from_ne_bytes((u_string::unit_count(&(digits))).to_ne_bytes()) < (i32::from_ne_bytes((TestTraceRender::TEST_TRACE_RENDER_MAX_SIGNIFICANT_DIGITS).to_ne_bytes())) {
                digits += &(u_string::substring(&all, i32::from_ne_bytes((cursor).to_ne_bytes()), i32::from_ne_bytes((u32::wrapping_add(cursor, 1)).to_ne_bytes())));
            } else {
                if !(u_string::unit_at(&all, cursor).as_ref().map_or(false, |v| v == &(48))) {
                    extended = true;
                }
            }
            cursor = u32::wrapping_add(cursor, 1);
        }
        return Ok(Some(DecimalShape::new(digits.as_str(), u32::wrapping_sub(point, first), extended)));
    }

    pub(crate) fn test_trace_render_float_text_render(c: u32, e: u32, p: u32, negative: bool) -> Result<String, UnsupportedCharacterFault> {
        let mut s = crate::runtime::int_text::IntText::int_text(c);
        if i32::from_ne_bytes((u_string::unit_count(&(s))).to_ne_bytes()) < (i32::from_ne_bytes((p).to_ne_bytes())) {
            s = string_tools::StringTools::string_tools_lpad(s.as_str(), &"0", i32::from_ne_bytes((p).to_ne_bytes()));
        }
        let point_after = i32::wrapping_add(i32::from_ne_bytes((e).to_ne_bytes()), 1);
        let mut out = Vec::<u16>::new();
        if negative {
            if let Some(&unit) = out.last() {
                if unit >= 55296 && unit <= 56319 && !"-".is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            out.extend("-".encode_utf16());
        }
        if point_after <= 0 {
            if let Some(&unit) = out.last() {
                if unit >= 55296 && unit <= 56319 && !"0.".is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            out.extend("0.".encode_utf16());
            for _ in 0..u32::try_from(-(point_after as i32)).unwrap_or(0) {
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !"0".is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                out.extend("0".encode_utf16());
            }
            if let Some(&unit) = out.last() {
                if unit >= 55296 && unit <= 56319 && !s.is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            out.extend(s.encode_utf16());
        } else {
            if point_after >= i32::from_ne_bytes((p).to_ne_bytes()) {
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !s.is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                out.extend(s.encode_utf16());
                for _ in p..u32::try_from(point_after).unwrap_or(0) {
                    if let Some(&unit) = out.last() {
                        if unit >= 55296 && unit <= 56319 && !"0".is_empty() {
                            return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                        }
                    }
                    out.extend("0".encode_utf16());
                }
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !".0".is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                out.extend(".0".encode_utf16());
            } else {
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !u_string::substring(&s, 0i32, i32::from_ne_bytes((point_after).to_ne_bytes())).is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                out.extend(u_string::substring(&s, 0i32, i32::from_ne_bytes((point_after).to_ne_bytes())).encode_utf16());
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !".".is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                out.extend(".".encode_utf16());
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !u_string::substring_from(&s, i32::from_ne_bytes((point_after).to_ne_bytes())).is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                out.extend(u_string::substring_from(&s, i32::from_ne_bytes((point_after).to_ne_bytes())).encode_utf16());
            }
        }
        return Ok(String::from_utf16(out.as_slice()).map_err(|_| UnsupportedCharacterFault { unit: u32::from(out[out.len() - 1]) })?);
    }

    pub fn test_trace_render_render_bool(value: bool) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_value_bool(value).as_str())?);
    }

    pub fn test_trace_render_render_null() -> String {
        return "-".to_string();
    }

    pub fn test_trace_render_render_int_array(values: &Vec<u32>) -> Result<String, UnsupportedCharacterFault> {
        let mut output = Vec::<u16>::new();
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !"[".is_empty() {
                return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
            }
        }
        output.extend("[".encode_utf16());
        let mut index = 0u32;
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0)).to_ne_bytes())) {
            if i32::from_ne_bytes((index).to_ne_bytes()) > (0) {
                if let Some(&unit) = output.last() {
                    if unit >= 55296 && unit <= 56319 && !", ".is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                output.extend(", ".encode_utf16());
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !TestTraceRender::test_trace_render_render_int(values[usize::try_from(index).unwrap_or(0)])?.is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            output.extend(TestTraceRender::test_trace_render_render_int(values[usize::try_from(index).unwrap_or(0)])?.encode_utf16());
            index = u32::wrapping_add(index, 1);
        }
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !"]".is_empty() {
                return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
            }
        }
        output.extend("]".encode_utf16());
        let text = String::from_utf16(output.as_slice()).map_err(|_| UnsupportedCharacterFault { unit: u32::from(output[output.len() - 1]) })?;
        return Ok(TestTraceRender::test_trace_render_cap(text.as_str())?);
    }

    pub fn test_trace_render_render_string_array(values: &[String]) -> Result<String, UnsupportedCharacterFault> {
        let mut output = Vec::<u16>::new();
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !"[".is_empty() {
                return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
            }
        }
        output.extend("[".encode_utf16());
        let mut index = 0u32;
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0)).to_ne_bytes())) {
            if i32::from_ne_bytes((index).to_ne_bytes()) > (0) {
                if let Some(&unit) = output.last() {
                    if unit >= 55296 && unit <= 56319 && !", ".is_empty() {
                        return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                    }
                }
                output.extend(", ".encode_utf16());
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !TestTraceRender::test_trace_render_render_string((values[usize::try_from(index).unwrap_or(0)]).clone().as_str())?.is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            output.extend(TestTraceRender::test_trace_render_render_string((values[usize::try_from(index).unwrap_or(0)]).clone().as_str())?.encode_utf16());
            index = u32::wrapping_add(index, 1);
        }
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !"]".is_empty() {
                return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
            }
        }
        output.extend("]".encode_utf16());
        let text = String::from_utf16(output.as_slice()).map_err(|_| UnsupportedCharacterFault { unit: u32::from(output[output.len() - 1]) })?;
        return Ok(TestTraceRender::test_trace_render_cap(text.as_str())?);
    }

    pub fn test_trace_render_legacy_list_text(parts: &Vec<String>) -> String {
        return format!("{}{}{}",
            "[",
            { let joined = parts; let mut out = String::new(); let n = joined.len(); let mut index1 = 0usize; while index1 < n { if index1 > 0 { out.push_str(&(", ")); } let _ = write!(out, "{}", joined[index1]); index1 += 1; } out },
            "]"
        );
    }

    pub fn test_trace_render_canonical_numbers(value: &str) -> Result<String, UnsupportedCharacterFault> {
        return Ok(TestTraceRender::test_trace_render_strip_whole_fraction(TestTraceRender::test_trace_render_expand_scientific(value, &u_string::units(value), u_string::unit_count(value))?.as_str())?);
    }

    pub fn test_trace_render_cap(value: &str) -> Result<String, UnsupportedCharacterFault> {
        let canonical = TestTraceRender::test_trace_render_canonical_numbers(value)?;
        if i32::from_ne_bytes((u_string::unit_count(&(canonical))).to_ne_bytes()) <= i32::from_ne_bytes((TestTraceRender::TEST_TRACE_RENDER_MAX_OPERAND_CHARS).to_ne_bytes()) {
            return Ok(canonical);
        }
        return Ok(format!("{}{}{}{}{}",
            u_string::substring(&canonical, 0i32, i32::from_ne_bytes((TestTraceRender::TEST_TRACE_RENDER_MAX_OPERAND_CHARS).to_ne_bytes())),
            "~",
            crate::runtime::int_text::IntText::int_text(u_string::unit_count(&(canonical))),
            "#",
            TestTraceRender::test_trace_render_fnv1a(canonical.as_str())
        ));
    }

    pub(crate) fn test_trace_render_escape(value: &str) -> String {
    let __units5 = u_string::units(&value);
    let __count5 = u_string::unit_count(&value);
        let mut output = String::new();
        let mut index = 0u32;
        let __units6 = u_string::units(&value);
        let __count6 = u_string::unit_count(&value);
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count5).to_ne_bytes())) {
            let code_unit = u_string::unit_at_from(&__units6, index);
            if code_unit.as_ref().map_or(false, |v| v == &(0)) {
                output += &("\\u0000");
            } else {
                output += &(u_string::escape_text(u_string::char_at_from(&__units6, index).as_str()));
            }
            index = u32::wrapping_add(index, 1);
        }
        return output;
    }

    pub(crate) fn test_trace_render_expand_scientific(value: &str, __units7: &[u16], __count7: u32) -> Result<String, UnsupportedCharacterFault> {
        let mut output = Vec::<u16>::new();
        let mut copied = 0u32;
        let mut index = 0u32;
                        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count7).to_ne_bytes())) {
            let code_unit = u_string::unit_at_from(&__units7, index).unwrap_or(0);
            if code_unit != 69 && code_unit != 101 {
                index = u32::wrapping_add(index, 1);
                continue;
            }
            let r#match = TestTraceRender::test_trace_render_scientific_match(value, index, copied, __units7, __count7);
            if r#match.is_none() {
                index = u32::wrapping_add(index, 1);
                continue;
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !u_string::substring(&value, i32::from_ne_bytes((copied).to_ne_bytes()), i32::from_ne_bytes(((r#match).as_ref().unwrap().start).to_ne_bytes())).is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            output.extend(u_string::substring(&value, i32::from_ne_bytes((copied).to_ne_bytes()), i32::from_ne_bytes(((r#match).as_ref().unwrap().start).to_ne_bytes())).encode_utf16());
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !TestTraceRender::test_trace_render_expand_mantissa(u_string::substring(&value, i32::from_ne_bytes(((r#match).as_ref().unwrap().start).to_ne_bytes()),
i32::from_ne_bytes(((r#match).as_ref().unwrap().mantissa_end).to_ne_bytes())).as_str(), (r#match).as_ref().unwrap().exponent)?.is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            output.extend(TestTraceRender::test_trace_render_expand_mantissa(u_string::substring(&value, i32::from_ne_bytes(((r#match).as_ref().unwrap().start).to_ne_bytes()), i32::from_ne_bytes(((r#match).as_ref().unwrap().mantissa_end).to_ne_bytes())).as_str(),
(r#match).as_ref().unwrap().exponent)?.encode_utf16());
            copied = (r#match).as_ref().unwrap().end;
            index = (r#match).as_ref().unwrap().end;
        }
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !u_string::substring(&value, i32::from_ne_bytes((copied).to_ne_bytes()), i32::from_ne_bytes((__count7).to_ne_bytes())).is_empty() {
                return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
            }
        }
        output.extend(u_string::substring(&value, i32::from_ne_bytes((copied).to_ne_bytes()), i32::from_ne_bytes((__count7).to_ne_bytes())).encode_utf16());
        return Ok(String::from_utf16(output.as_slice()).map_err(|_| UnsupportedCharacterFault { unit: u32::from(output[output.len() - 1]) })?);
    }

    pub(crate) fn test_trace_render_strip_whole_fraction(value: &str) -> Result<String, UnsupportedCharacterFault> {
    let __units9 = u_string::units(&value);
    let __count9 = u_string::unit_count(&value);
        let mut output = Vec::<u16>::new();
        let mut index = 0u32;
        let __units10 = u_string::units(&value);
        let __count10 = u_string::unit_count(&value);
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count9).to_ne_bytes())) {
            if u_string::unit_at_from(&__units10, index).as_ref().map_or(false, |v| v == &(46)) && (i32::from_ne_bytes((index).to_ne_bytes())) > (0) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&__units9, u32::wrapping_sub(index, 1))).as_ref().unwrap())
{
                let mut cursor = u32::wrapping_add(index, 1);
                let __units11 = u_string::units(&value);
                let __count11 = u_string::unit_count(&value);
                while (i32::from_ne_bytes((cursor).to_ne_bytes())) < (i32::from_ne_bytes((__count9).to_ne_bytes())) && u_string::unit_at_from(&__units9, cursor).as_ref().map_or(false, |v| v == &(48)) {
                    cursor = u32::wrapping_add(cursor, 1);
                }
                if i32::from_ne_bytes((cursor).to_ne_bytes()) > (i32::from_ne_bytes((u32::wrapping_add(index, 1)).to_ne_bytes())) && (cursor == __count9 || !TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&__units9, cursor)).as_ref().unwrap()) &&
!(u_string::unit_at_from(&__units9, cursor).as_ref().map_or(false, |v| v == &(46)))) {
                    index = cursor;
                    continue;
                }
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !u_string::char_at_from(&__units10, index).is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            output.extend(u_string::char_at_from(&__units10, index).encode_utf16());
            index = u32::wrapping_add(index, 1);
        }
        return Ok(String::from_utf16(output.as_slice()).map_err(|_| UnsupportedCharacterFault { unit: u32::from(output[output.len() - 1]) })?);
    }

    pub(crate) fn test_trace_render_scientific_match(s: &str, e_index: u32, floor: u32, units: &[u16], count: u32) -> Option<ScientificMatch> {
        let mut i = u32::wrapping_add(e_index, 1);
        if i32::from_ne_bytes((i).to_ne_bytes()) < (i32::from_ne_bytes((count).to_ne_bytes())) && (u_string::unit_at_from(&units, i).as_ref().map_or(false, |v| v == &(43)) || u_string::unit_at_from(&units, i).as_ref().map_or(false, |v| v == &(45))) {
            i = u32::wrapping_add(i, 1);
        }
        let digits_start = i;
                        while (i32::from_ne_bytes((i).to_ne_bytes())) < (i32::from_ne_bytes((count).to_ne_bytes())) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&units, i)).as_ref().unwrap()) {
            i = u32::wrapping_add(i, 1);
        }
        if i32::from_ne_bytes((u32::wrapping_sub(i, digits_start)).to_ne_bytes()) > (3) {
            return None;
        }
        if i == digits_start {
            return None;
        }
        let end = i;
        let exponent = TestTraceRender::test_trace_render_parse_exponent(s, u32::wrapping_add(e_index, 1), end);
        let last = u32::wrapping_sub(e_index, 1);
        if i32::from_ne_bytes((last).to_ne_bytes()) < (i32::from_ne_bytes((floor).to_ne_bytes())) || !TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&units, last)).as_ref().unwrap()) {
            return None;
        }
        let mut run_start = last;
        while (i32::from_ne_bytes((run_start).to_ne_bytes())) > (i32::from_ne_bytes((floor).to_ne_bytes())) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&units, u32::wrapping_sub(run_start, 1))).as_ref().unwrap()) {
            run_start = u32::wrapping_sub(run_start, 1);
        }
        let lead: u32;
        if i32::from_ne_bytes((run_start).to_ne_bytes()) > (i32::from_ne_bytes((u32::wrapping_add(floor, 1)).to_ne_bytes())) && u_string::unit_at_from(&units, u32::wrapping_sub(run_start, 1)).as_ref().map_or(false, |v| v == &(46)) &&
TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&units, u32::wrapping_sub(run_start, 2))).as_ref().unwrap()) {
            lead = u32::wrapping_sub(run_start, 2);
        } else {
            if run_start != last {
                return None;
            }
            lead = last;
        }
        if i32::from_ne_bytes((lead).to_ne_bytes()) > (0) && u_string::unit_at_from(&units, u32::wrapping_sub(lead, 1)).as_ref().map_or(false, |v| v == &(45)) && (i32::from_ne_bytes((u32::wrapping_sub(lead, 1)).to_ne_bytes())) >= i32::from_ne_bytes((floor).to_ne_bytes()) {
            let before_minus = i32::from_ne_bytes((lead).to_ne_bytes()) >= 2 && (TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&units, u32::wrapping_sub(lead, 2))).as_ref().unwrap()) || u_string::unit_at_from(&units, u32::wrapping_sub(lead,
2)).as_ref().map_or(false, |v| v == &(46)));
            if !before_minus {
                return Some(ScientificMatch::new(u32::wrapping_sub(lead, 1), e_index, end, exponent));
            }
            return Some(ScientificMatch::new(lead, e_index, end, exponent));
        }
        let before_digit = i32::from_ne_bytes((lead).to_ne_bytes()) > (0) && (TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(&units, u32::wrapping_sub(lead, 1))).as_ref().unwrap()) || u_string::unit_at_from(&units, u32::wrapping_sub(lead,
1)).as_ref().map_or(false, |v| v == &(46)));
        if !before_digit {
            return Some(ScientificMatch::new(lead, e_index, end, exponent));
        }
        return None;
    }

    pub(crate) fn test_trace_render_parse_exponent(s: &str, from: u32, to: u32) -> u32 {
    let __units14 = u_string::units(&s);
    let __count14 = u_string::unit_count(&s);
        let mut index = from;
        let mut negative = false;
        if i32::from_ne_bytes((index).to_ne_bytes()) < (i32::from_ne_bytes((to).to_ne_bytes())) && (u_string::unit_at_from(&__units14, index).as_ref().map_or(false, |v| v == &(43)) || u_string::unit_at_from(&__units14, index).as_ref().map_or(false, |v| v == &(45))) {
            negative = u_string::unit_at_from(&__units14, index).as_ref().map_or(false, |v| v == &(45));
            index = u32::wrapping_add(index, 1);
        }
        let mut value = 0u32;
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((to).to_ne_bytes())) {
            value = u32::wrapping_sub(u32::wrapping_add(u32::wrapping_mul(value, 10), u_string::unit_at_from(&__units14, index).unwrap_or(0)), 48);
            index = u32::wrapping_add(index, 1);
        }
        return if negative { u32::from_ne_bytes((-(value as i32)).to_ne_bytes()) } else { value };
    }

    pub(crate) fn test_trace_render_expand_mantissa(mantissa: &str, exponent: u32) -> Result<String, UnsupportedCharacterFault> {
        let mut sign = String::new();
        let mut value = (mantissa.to_string()).clone();
        if i32::from_ne_bytes((u_string::unit_count(&(value))).to_ne_bytes()) > (0) && u_string::unit_at(&value, 0u32).as_ref().map_or(false, |v| v == &(45)) {
            sign = "-".to_string();
            value = u_string::substring_from(&value, 1i32);
        }
        let mut dot_index = 4294967295u32;
        let mut index = 0u32;
        let __units15 = u_string::units(&value);
        let __count15 = u_string::unit_count(&value);
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count15).to_ne_bytes())) {
            if u_string::unit_at_from(&__units15, index).as_ref().map_or(false, |v| v == &(46)) {
                dot_index = index;
                break;
            }
            index = u32::wrapping_add(index, 1);
        }
        let mut digits = if dot_index > 2147483647 { (value.to_string()).clone() } else { format!("{}{}",
            u_string::substring(&value, 0i32, i32::from_ne_bytes((dot_index).to_ne_bytes())),
            u_string::substring_from(&value, i32::from_ne_bytes((u32::wrapping_add(dot_index, 1)).to_ne_bytes()))
        ).to_string() };
        while (i32::from_ne_bytes((u_string::unit_count(&(digits))).to_ne_bytes())) > (1) && u_string::unit_at(&digits, u32::wrapping_sub(u_string::unit_count(&(digits)), 1)).as_ref().map_or(false, |v| v == &(48)) {
            digits = u_string::substring(&digits, 0i32, i32::from_ne_bytes((u32::wrapping_sub(u_string::unit_count(&(digits)), 1)).to_ne_bytes()));
        }
        if i32::from_ne_bytes((exponent).to_ne_bytes()) > (400) || (i32::from_ne_bytes((exponent).to_ne_bytes())) < (i32::from_ne_bytes((4294966896u32).to_ne_bytes())) {
            return Ok(format!("{}{}",
            sign,
            value
        ));
        }
        let decimal_position = i32::wrapping_add(i32::from_ne_bytes((if dot_index > 2147483647 { u_string::unit_count(&(value)) } else { dot_index }).to_ne_bytes()), i32::from_ne_bytes((exponent).to_ne_bytes()));
        if decimal_position <= 0 {
            return Ok(format!("{}{}{}{}",
            sign,
            "0.",
            TestTraceRender::test_trace_render_zeroes(u32::from_ne_bytes((-(decimal_position as i32)).to_ne_bytes()))?,
            digits
        ));
        }
        if decimal_position >= i32::from_ne_bytes((u_string::unit_count(&(digits))).to_ne_bytes()) {
            return Ok(format!("{}{}{}",
            sign,
            digits,
            TestTraceRender::test_trace_render_zeroes(u32::from_ne_bytes((i32::wrapping_sub(decimal_position, i32::from_ne_bytes((u_string::unit_count(&(digits))).to_ne_bytes()))).to_ne_bytes()))?
        ));
        }
        return Ok(format!("{}{}{}{}",
            sign,
            u_string::substring(&digits, 0i32, i32::from_ne_bytes((decimal_position).to_ne_bytes())),
            ".",
            u_string::substring_from(&digits, i32::from_ne_bytes((decimal_position).to_ne_bytes()))
        ));
    }

    pub(crate) fn test_trace_render_zeroes(count: u32) -> Result<String, UnsupportedCharacterFault> {
        let mut output = Vec::<u16>::new();
        for _ in 0..count {
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !"0".is_empty() {
                    return Err(UnsupportedCharacterFault { unit: u32::from(unit) });
                }
            }
            output.extend("0".encode_utf16());
        }
        return Ok(String::from_utf16(output.as_slice()).map_err(|_| UnsupportedCharacterFault { unit: u32::from(output[output.len() - 1]) })?);
    }

    pub(crate) fn test_trace_render_is_digit(code_unit: u32) -> bool {
        return (i32::from_ne_bytes((code_unit).to_ne_bytes())) >= 48 && (i32::from_ne_bytes((code_unit).to_ne_bytes())) <= 57;
    }

    pub(crate) fn test_trace_render_fnv1a(value: &str) -> String {
    let __units16 = u_string::units(&value);
    let __count16 = u_string::unit_count(&value);
        let mut hash = 2166136261u32;
        let mut index = 0u32;
        let __units17 = u_string::units(&value);
        let __count17 = u_string::unit_count(&value);
        while (i32::from_ne_bytes((index).to_ne_bytes())) < (i32::from_ne_bytes((__count16).to_ne_bytes())) {
            hash = hash ^ u_string::unit_at_from(&__units17, index).unwrap_or(0);
            hash = TestTraceRender::test_trace_render_multiply_fnv_prime(hash);
            index = u32::wrapping_add(index, 1);
        }
        let first = u32::from(hash.to_be_bytes()[0]);
        let second = u32::from(hash.to_be_bytes()[1]);
        let third = u32::from(hash.to_be_bytes()[2]);
        let fourth = u32::from(hash.to_be_bytes()[3]);
        let mut output = format!("{}{}{}{}",
            TestTraceRender::test_trace_render_hex_byte(first),
            TestTraceRender::test_trace_render_hex_byte(second),
            TestTraceRender::test_trace_render_hex_byte(third),
            TestTraceRender::test_trace_render_hex_byte(fourth)
        );
        while (i32::from_ne_bytes((u_string::unit_count(&(output))).to_ne_bytes())) > (1) && u_string::unit_at(&output, 0u32).as_ref().map_or(false, |v| v == &(48)) {
            output = u_string::substring_from(&output, 1i32);
        }
        return output;
    }

    pub(crate) fn test_trace_render_multiply_fnv_prime(value: u32) -> u32 {
        let low = value & 65535;
        let high = value >> 16 & 65535;
        let low_product = u32::wrapping_mul(low, 403);
        let high_product = u32::wrapping_add(u32::wrapping_add(u32::wrapping_mul(high, 403), u32::wrapping_mul(low, 256)), (low_product) / (65536));
        return (high_product & 65535) << (16) | low_product & 65535;
    }

    pub(crate) fn test_trace_render_hex_byte(value: u32) -> String {
        return format!("{}{}",
            u_string::substring(&TestTraceRender::TEST_TRACE_RENDER_HEX.to_string(), i32::from_ne_bytes((value >> 4 & 15).to_ne_bytes()), i32::from_ne_bytes((u32::wrapping_add(value >> 4 & 15, 1)).to_ne_bytes())),
            u_string::substring(&TestTraceRender::TEST_TRACE_RENDER_HEX.to_string(), i32::from_ne_bytes((value & 15).to_ne_bytes()), i32::from_ne_bytes((u32::wrapping_add(value & 15, 1)).to_ne_bytes()))
        );
    }
}

#[derive(Clone, PartialEq)]
pub struct DecimalShape {
    pub digits: String,
    pub position: u32,
    pub extended: bool,
}

impl DecimalShape {
    pub fn new(digits: &str, position: u32, extended: bool) -> Self {
        Self {
            digits: digits.to_string(),
            position,
            extended,
        }
    }
}

#[derive(Clone, PartialEq)]
pub struct ScientificMatch {
    pub start: u32,
    pub mantissa_end: u32,
    pub end: u32,
    pub exponent: u32,
}

impl ScientificMatch {
    pub fn new(start: u32, mantissa_end: u32, end: u32, exponent: u32) -> Self {
        Self {
            start,
            mantissa_end,
            end,
            exponent,
        }
    }
}


// ---------------------------------------------------------------------------
// The measurement. `expand_scientific` is the function the historical Tiqian test
// reaches through `TestTraceRender::test_trace_render_canonical_numbers`; its inner
// `scientific_match` walks the whole string once per 'e'/'E' it sees.
fn sample(n: usize) -> String {
    let mut s = String::with_capacity(n);
    while s.len() < n { s.push_str("1e2"); }
    s
}

fn main() {
    let n: usize = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(100_000);
    let text = sample(n);
    UNITS_CALLS.store(0, Ordering::Relaxed);
    UNITS_BYTES.store(0, Ordering::Relaxed);
    UNIT_AT_CALLS.store(0, Ordering::Relaxed);
    PRE_UNITS_CALLS.store(0, Ordering::Relaxed);

    let t0 = std::time::Instant::now();
    let units: Vec<u16> = u_string::units(&text);
    let count = u_string::unit_count(&text);
    let precompute_ms = t0.elapsed().as_millis();
    let after_precompute = UNITS_CALLS.load(Ordering::Relaxed);

    let t1 = std::time::Instant::now();
    let out = TestTraceRender::test_trace_render_expand_scientific(&text, &units, count).unwrap_or_default();
    let walk_ms = t1.elapsed().as_millis();

    println!("bytes={} precompute_units_calls={} precompute_ms={} walk_units_calls={} walk_unit_at_calls={} walk_ms={} out_b={}",
        text.len(), after_precompute, precompute_ms,
        UNITS_CALLS.load(Ordering::Relaxed) - after_precompute,
        UNIT_AT_CALLS.load(Ordering::Relaxed), walk_ms, out.len());
}
