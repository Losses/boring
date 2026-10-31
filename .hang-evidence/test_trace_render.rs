use crate::org::tiqian::test::trace::trace_format::TraceFormat;
use crate::runtime::fp_helper::FPHelper;
use crate::runtime::string_tools;
use crate::runtime::u_string;
use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;
use crate::std::u_string_exception::UStringFault;
use std::cell::RefCell;
use std::fmt::Write;
use std::rc::Rc;


#[derive(Clone, Copy)]
pub struct TestTraceRender;

impl TestTraceRender {
    const TEST_TRACE_RENDER_MAX_OPERAND_CHARS: u32 = 240;
    const TEST_TRACE_RENDER_HEX: &UStr = unsafe { &*(&[0x0030u16, 0x0031u16, 0x0032u16, 0x0033u16, 0x0034u16, 0x0035u16, 0x0036u16, 0x0037u16, 0x0038u16, 0x0039u16, 0x0061u16, 0x0062u16, 0x0063u16, 0x0064u16, 0x0065u16, 0x0066u16] as *const [u16] as *const crate::runtime::u_string::UStr) };
    const TEST_TRACE_RENDER_MAX_SIGNIFICANT_DIGITS: u32 = 9;

    pub fn test_trace_render_escape_operand(value: &UStr) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TestTraceRender::test_trace_render_escape(value).as_ustr())?);
    }

    pub fn test_trace_render_render_string(value: &UStr) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_cap(UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("'")); __s += TestTraceRender::test_trace_render_escape(value).as_ustr(); __s += &(UString::from("'")); __s }).as_str()).as_ustr())?);
    }

    pub fn test_trace_render_render_int(value: u32) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_i(value).as_ustr())?);
    }

    pub fn test_trace_render_render_long(value: u32) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_value_long(value).as_ustr())?);
    }

    pub fn test_trace_render_render_float(value: f64) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_fd(value, 6).as_ustr())?);
    }

    pub fn test_trace_render_float_text(value: f64) -> Result<UString, UStringFault> {
        let negative = value < (0 as f64);
        let v = (value).abs();
        if v == 0 as f64 {
            return Ok(if negative { UString::from("-0.0") } else { UString::from("0.0") });
        }
        let shape = TestTraceRender::test_trace_render_decimal_shape(v)?;
        if shape.is_none() {
            return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += (if negative { UString::from("-") } else { UString::from("") }).as_ustr(); __s += UString::from(format!("{}", crate::runtime::fp_helper::FPHelper::format_float(v)).as_str()).as_ustr(); __s }).as_str()));
        }
        let digits = ((shape).as_ref().unwrap().borrow().digits).to_ustring().clone();
        let width = u_string::unit_count(&(digits));
        let position = (shape).as_ref().unwrap().borrow().position;
        let target_bits = FPHelper::float_to_i32(v);
        let mut p = 1u32;
        while (i32::from_ne_bytes(((p) as i32).to_ne_bytes())) <= 9 {
            let exp = u32::wrapping_sub(position, p);
            let base = if i32::from_ne_bytes(((p) as i32).to_ne_bytes()) >= i32::from_ne_bytes(((width) as i32).to_ne_bytes()) { u32::wrapping_mul(TestTraceRender::test_trace_render_decimal_int(digits.as_ustr()), TestTraceRender::test_trace_render_pow10_int(u32::wrapping_sub(p, width))) } else { TestTraceRender::test_trace_render_decimal_int(u_string::substring(&digits, 0i32, i32::from_ne_bytes(((p) as i32).to_ne_bytes())).as_ustr()) };
            let frac = TestTraceRender::test_trace_render_fraction_after(digits.as_ustr(), p, (shape).as_ref().unwrap().borrow().extended);
            let mut best = 4294967295u32;
            let mut best_dist = f64::INFINITY;
            let mut c = u32::wrapping_sub(base, 1);
            while (i32::from_ne_bytes(((c) as i32).to_ne_bytes())) <= i32::from_ne_bytes(((u32::wrapping_add(base, 2)) as i32).to_ne_bytes()) {
                if i32::from_ne_bytes(((c) as i32).to_ne_bytes()) >= 1 {
                    let candidate_text = { let mut __s = UString::new(); __s += UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(c)).as_str()).as_ustr(); __s += &(UString::from("e")); __s += UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(exp)).as_str()).as_ustr(); __s };
                    let cand = u_string::parse_f64(&(candidate_text));
                    if FPHelper::float_to_i32(cand) == target_bits {
                        let dist = (format!("{}", (i32::from_ne_bytes(((u32::wrapping_sub(c, base)) as i32).to_ne_bytes()))).parse::<f64>().unwrap_or(0.0) - frac).abs();
                        if dist < (best_dist) || dist == best_dist && u32::from_ne_bytes(((i32::from_ne_bytes(((c) as i32).to_ne_bytes()) % 2i32) as u32).to_ne_bytes()) == 0 {
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
        return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += (if negative { UString::from("-") } else { UString::from("") }).as_ustr(); __s += UString::from(format!("{}", crate::runtime::fp_helper::FPHelper::format_float(v)).as_str()).as_ustr(); __s }).as_str()));
    }

    pub(crate) fn test_trace_render_decimal_int(digits: &UStr) -> u32 {
    let __units = digits.as_slice();
    let __count = u_string::unit_count(&digits);
        let mut value = 0u32;
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count) as i32).to_ne_bytes())) {
            value = u32::wrapping_sub(u32::wrapping_add(u32::wrapping_mul(value, 10), u_string::unit_at_from(__units, index).unwrap_or(0)), 48);
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

    pub(crate) fn test_trace_render_fraction_after(digits: &UStr, p: u32, extended: bool) -> f64 {
    let __units2 = digits.as_slice();
    let __count2 = u_string::unit_count(&digits);
        if i32::from_ne_bytes(((p) as i32).to_ne_bytes()) >= i32::from_ne_bytes(((__count2) as i32).to_ne_bytes()) {
            return 0.0f64;
        }
        let frac = u_string::parse_f64(&({ let mut __s = UString::new(); __s += &(UString::from("0.")); __s += u_string::substring_from(&digits, i32::from_ne_bytes(((p) as i32).to_ne_bytes())).as_ustr(); __s }));
        if extended && frac == 0.5f64 {
            return 0.75f64;
        }
        return frac;
    }

    pub(crate) fn test_trace_render_decimal_shape(v: f64) -> Result<Option<Rc<RefCell<DecimalShape>>>, UStringFault> {
        if !(v).is_finite() {
            return Ok(None);
        }
        let plain = UString::from(format!("{}", TestTraceRender::test_trace_render_expand_scientific(UString::from(format!("{}", crate::runtime::fp_helper::FPHelper::format_float(v)).as_str()).as_ustr())?).as_str());
        let mut point = u_string::unit_count(&(plain));
        let mut index = 0u32;
        let __units3 = plain.as_slice();
        let __count3 = u_string::unit_count(&plain);
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count3) as i32).to_ne_bytes())) {
            if matches!(u_string::unit_at_from(__units3, index).as_ref(), Some(__v) if __v == &(46)) {
                point = index;
                break;
            }
            index = u32::wrapping_add(index, 1);
        }
        let all = { let mut __s = UString::new(); __s += u_string::substring(&plain, 0i32, i32::from_ne_bytes(((point) as i32).to_ne_bytes())).as_ustr(); __s += u_string::substring_from(&plain, i32::from_ne_bytes(((u32::wrapping_add(point, 1)) as i32).to_ne_bytes())).as_ustr(); __s };
        let mut first = 0u32;
        let __units4 = all.as_slice();
        let __count4 = u_string::unit_count(&all);
        while (i32::from_ne_bytes(((first) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count4) as i32).to_ne_bytes())) && matches!(u_string::unit_at_from(__units4, first).as_ref(), Some(__v) if __v == &(48)) {
            first = u32::wrapping_add(first, 1);
        }
        if first == u_string::unit_count(&(all)) {
            return Ok(None);
        }
        let mut last = u_string::unit_count(&(all));
        while (i32::from_ne_bytes(((last) as i32).to_ne_bytes())) > (i32::from_ne_bytes(((u32::wrapping_add(first, 1)) as i32).to_ne_bytes())) && matches!(u_string::unit_at(&all, u32::wrapping_sub(last, 1)).as_ref(), Some(__v) if __v == &(48)) {
            last = u32::wrapping_sub(last, 1);
        }
        let mut digits = UString::new();
        let mut extended = false;
        let mut cursor = first;
        while (i32::from_ne_bytes(((cursor) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((last) as i32).to_ne_bytes())) {
            if i32::from_ne_bytes(((u_string::unit_count(&(digits))) as i32).to_ne_bytes()) < (i32::from_ne_bytes(((TestTraceRender::TEST_TRACE_RENDER_MAX_SIGNIFICANT_DIGITS) as i32).to_ne_bytes())) {
                digits += &(u_string::substring(&all, i32::from_ne_bytes(((cursor) as i32).to_ne_bytes()), i32::from_ne_bytes(((u32::wrapping_add(cursor, 1)) as i32).to_ne_bytes())));
            } else {
                if !(matches!(u_string::unit_at(&all, cursor).as_ref(), Some(__v) if __v == &(48))) {
                    extended = true;
                }
            }
            cursor = u32::wrapping_add(cursor, 1);
        }
        return Ok(Some(DecimalShape::new(digits.as_ustr(), u32::wrapping_sub(point, first), extended)));
    }

    pub(crate) fn test_trace_render_float_text_render(c: u32, e: u32, p: u32, negative: bool) -> Result<UString, UStringFault> {
        let mut s = UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(c)).as_str());
        if i32::from_ne_bytes(((u_string::unit_count(&(s))) as i32).to_ne_bytes()) < (i32::from_ne_bytes(((p) as i32).to_ne_bytes())) {
            s = string_tools::StringTools::string_tools_lpad(s.as_ustr(), UStr::new(&[48]), i32::from_ne_bytes(((p) as i32).to_ne_bytes()));
        }
        let point_after = i32::wrapping_add(i32::from_ne_bytes(((e) as i32).to_ne_bytes()), 1);
        let mut out = Vec::<u16>::new();
        if negative {
            if let Some(&unit) = out.last() {
                if unit >= 55296 && unit <= 56319 && !UString::from("-").is_empty() {
                    if !match (UString::from("-")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            out.extend(UString::from("-").encode_utf16());
        }
        if point_after <= 0 {
            if let Some(&unit) = out.last() {
                if unit >= 55296 && unit <= 56319 && !UString::from("0.").is_empty() {
                    if !match (UString::from("0.")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            out.extend(UString::from("0.").encode_utf16());
            for _ in 0..u32::try_from(-(point_after as i32)).unwrap_or(0) {
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !UString::from("0").is_empty() {
                        if !match (UString::from("0")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                out.extend(UString::from("0").encode_utf16());
            }
            if let Some(&unit) = out.last() {
                if unit >= 55296 && unit <= 56319 && !s.is_empty() {
                    if !match (s).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            out.extend(s.encode_utf16());
        } else {
            if point_after >= i32::from_ne_bytes(((p) as i32).to_ne_bytes()) {
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !s.is_empty() {
                        if !match (s).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                out.extend(s.encode_utf16());
                for _ in p..u32::try_from(point_after).unwrap_or(0) {
                    if let Some(&unit) = out.last() {
                        if unit >= 55296 && unit <= 56319 && !UString::from("0").is_empty() {
                            if !match (UString::from("0")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                                return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                            }
                        }
                    }
                    out.extend(UString::from("0").encode_utf16());
                }
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !UString::from(".0").is_empty() {
                        if !match (UString::from(".0")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                out.extend(UString::from(".0").encode_utf16());
            } else {
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !u_string::substring(&s, 0i32, i32::from_ne_bytes(((point_after) as i32).to_ne_bytes())).is_empty() {
                        if !match (u_string::substring(&s, 0i32, i32::from_ne_bytes(((point_after) as i32).to_ne_bytes()))).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                out.extend(u_string::substring(&s, 0i32, i32::from_ne_bytes(((point_after) as i32).to_ne_bytes())).encode_utf16());
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !UString::from(".").is_empty() {
                        if !match (UString::from(".")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                out.extend(UString::from(".").encode_utf16());
                if let Some(&unit) = out.last() {
                    if unit >= 55296 && unit <= 56319 && !u_string::substring_from(&s, i32::from_ne_bytes(((point_after) as i32).to_ne_bytes())).is_empty() {
                        if !match (u_string::substring_from(&s, i32::from_ne_bytes(((point_after) as i32).to_ne_bytes()))).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                out.extend(u_string::substring_from(&s, i32::from_ne_bytes(((point_after) as i32).to_ne_bytes())).encode_utf16());
            }
        }
        return Ok(UString::from_utf16(out.as_slice()).map_err(|_| UStringFault::UnpairedSurrogate { unit: u32::from(out[out.len() - 1]) })?);
    }

    pub fn test_trace_render_render_bool(value: bool) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_cap(TraceFormat::trace_format_value_bool(value).as_ustr())?);
    }

    pub fn test_trace_render_render_null() -> UString {
        return UString::from("-").to_ustring();
    }

    pub fn test_trace_render_render_int_array(values: &Vec<u32>) -> Result<UString, UStringFault> {
        let mut output = Vec::<u16>::new();
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !UString::from("[").is_empty() {
                if !match (UString::from("[")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                    return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                }
            }
        }
        output.extend(UString::from("[").encode_utf16());
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0)) as i32).to_ne_bytes())) {
            if i32::from_ne_bytes(((index) as i32).to_ne_bytes()) > (0) {
                if let Some(&unit) = output.last() {
                    if unit >= 55296 && unit <= 56319 && !UString::from(", ").is_empty() {
                        if !match (UString::from(", ")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                output.extend(UString::from(", ").encode_utf16());
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !TestTraceRender::test_trace_render_render_int(values[usize::try_from(index).unwrap_or(0)])?.is_empty() {
                    if !match (TestTraceRender::test_trace_render_render_int(values[usize::try_from(index).unwrap_or(0)])?).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            output.extend(TestTraceRender::test_trace_render_render_int(values[usize::try_from(index).unwrap_or(0)])?.encode_utf16());
            index = u32::wrapping_add(index, 1);
        }
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !UString::from("]").is_empty() {
                if !match (UString::from("]")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                    return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                }
            }
        }
        output.extend(UString::from("]").encode_utf16());
        let text = UString::from_utf16(output.as_slice()).map_err(|_| UStringFault::UnpairedSurrogate { unit: u32::from(output[output.len() - 1]) })?;
        return Ok(TestTraceRender::test_trace_render_cap(text.as_ustr())?);
    }

    pub fn test_trace_render_render_string_array(values: &[UString]) -> Result<UString, UStringFault> {
        let mut output = Vec::<u16>::new();
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !UString::from("[").is_empty() {
                if !match (UString::from("[")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                    return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                }
            }
        }
        output.extend(UString::from("[").encode_utf16());
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((u32::try_from((values.len()) & 0xFFFF_FFFF).unwrap_or(0)) as i32).to_ne_bytes())) {
            if i32::from_ne_bytes(((index) as i32).to_ne_bytes()) > (0) {
                if let Some(&unit) = output.last() {
                    if unit >= 55296 && unit <= 56319 && !UString::from(", ").is_empty() {
                        if !match (UString::from(", ")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                            return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                        }
                    }
                }
                output.extend(UString::from(", ").encode_utf16());
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !TestTraceRender::test_trace_render_render_string((values[usize::try_from(index).unwrap_or(0)]).clone().as_ustr())?.is_empty() {
                    if !match (TestTraceRender::test_trace_render_render_string((values[usize::try_from(index).unwrap_or(0)]).clone().as_ustr())?).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            output.extend(TestTraceRender::test_trace_render_render_string((values[usize::try_from(index).unwrap_or(0)]).clone().as_ustr())?.encode_utf16());
            index = u32::wrapping_add(index, 1);
        }
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !UString::from("]").is_empty() {
                if !match (UString::from("]")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                    return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                }
            }
        }
        output.extend(UString::from("]").encode_utf16());
        let text = UString::from_utf16(output.as_slice()).map_err(|_| UStringFault::UnpairedSurrogate { unit: u32::from(output[output.len() - 1]) })?;
        return Ok(TestTraceRender::test_trace_render_cap(text.as_ustr())?);
    }

    pub fn test_trace_render_legacy_list_text(parts: &Vec<UString>) -> UString {
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("[")); __s += UString::from(format!("{}", { let joined = parts; let mut out = String::new(); let n = joined.len(); let mut index1 = 0usize; while index1 < n { if index1 > 0 { out.push_str(", "); } let _ = write!(out, "{}", joined[index1]); index1 += 1; } UString::from(out.as_str()) }).as_str()).as_ustr(); __s += &(UString::from("]")); __s }).as_str());
    }

    pub fn test_trace_render_canonical_numbers(value: &UStr) -> Result<UString, UStringFault> {
        return Ok(TestTraceRender::test_trace_render_strip_whole_fraction(TestTraceRender::test_trace_render_expand_scientific(value)?.as_ustr())?);
    }

    pub fn test_trace_render_cap(value: &UStr) -> Result<UString, UStringFault> {
        let canonical = TestTraceRender::test_trace_render_canonical_numbers(value)?;
        if i32::from_ne_bytes(((u_string::unit_count(&(canonical))) as i32).to_ne_bytes()) <= i32::from_ne_bytes(((TestTraceRender::TEST_TRACE_RENDER_MAX_OPERAND_CHARS) as i32).to_ne_bytes()) {
            return Ok(canonical);
        }
        return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += u_string::substring(&canonical, 0i32, i32::from_ne_bytes(((TestTraceRender::TEST_TRACE_RENDER_MAX_OPERAND_CHARS) as i32).to_ne_bytes())).as_ustr(); __s += &(UString::from("~")); __s += &(UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(u_string::unit_count(&(canonical)))).as_str())); __s += &(UString::from("#")); __s += TestTraceRender::test_trace_render_fnv1a(canonical.as_ustr()).as_ustr(); __s }).as_str()));
    }

    pub(crate) fn test_trace_render_escape(value: &UStr) -> UString {
    let __units5 = value.as_slice();
    let __count5 = u_string::unit_count(&value);
        let mut output = UString::new();
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count5) as i32).to_ne_bytes())) {
            let code_unit = u_string::unit_at_from(__units5, index);
            if matches!(code_unit.as_ref(), Some(__v) if __v == &(0)) {
                output += &(UString::from("\\u0000"));
            } else {
                output += &(TraceFormat::trace_format_escape_text(u_string::char_at_from(__units5, index).as_ustr()));
            }
            index = u32::wrapping_add(index, 1);
        }
        return output;
    }

    pub(crate) fn test_trace_render_expand_scientific(value: &UStr) -> Result<UString, UStringFault> {
    let __units7 = value.as_slice();
    let __count7 = u_string::unit_count(&value);
        let mut output = Vec::<u16>::new();
        let mut copied = 0u32;
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count7) as i32).to_ne_bytes())) {
            let code_unit = u_string::unit_at_from(__units7, index).unwrap_or(0);
            if code_unit != 69 && code_unit != 101 {
                index = u32::wrapping_add(index, 1);
                continue;
            }
            let r#match = TestTraceRender::test_trace_render_scientific_match(value, index, copied);
            if r#match.is_none() {
                index = u32::wrapping_add(index, 1);
                continue;
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !u_string::substring(&value, i32::from_ne_bytes(((copied) as i32).to_ne_bytes()), i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().start) as i32).to_ne_bytes())).is_empty() {
                    if !match (u_string::substring(&value, i32::from_ne_bytes(((copied) as i32).to_ne_bytes()), i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().start) as i32).to_ne_bytes()))).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343,
None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            output.extend(u_string::substring(&value, i32::from_ne_bytes(((copied) as i32).to_ne_bytes()), i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().start) as i32).to_ne_bytes())).encode_utf16());
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !TestTraceRender::test_trace_render_expand_mantissa(u_string::substring(&value, i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().start) as i32).to_ne_bytes()), i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().mantissa_end) as i32).to_ne_bytes())).as_ustr(), (r#match).as_ref().unwrap().borrow().exponent)?.is_empty() {
                    if !match (TestTraceRender::test_trace_render_expand_mantissa(u_string::substring(&value, i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().start) as i32).to_ne_bytes()), i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().mantissa_end) as i32).to_ne_bytes())).as_ustr(), (r#match).as_ref().unwrap().borrow().exponent)?).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            output.extend(TestTraceRender::test_trace_render_expand_mantissa(u_string::substring(&value, i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().start) as i32).to_ne_bytes()), i32::from_ne_bytes((((r#match).as_ref().unwrap().borrow().mantissa_end) as i32).to_ne_bytes())).as_ustr(), (r#match).as_ref().unwrap().borrow().exponent)?.encode_utf16());
            copied = (r#match).as_ref().unwrap().borrow().end;
            index = (r#match).as_ref().unwrap().borrow().end;
        }
        if let Some(&unit) = output.last() {
            if unit >= 55296 && unit <= 56319 && !u_string::substring(&value, i32::from_ne_bytes(((copied) as i32).to_ne_bytes()), i32::from_ne_bytes(((__count7) as i32).to_ne_bytes())).is_empty() {
                if !match (u_string::substring(&value, i32::from_ne_bytes(((copied) as i32).to_ne_bytes()), i32::from_ne_bytes(((__count7) as i32).to_ne_bytes()))).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                    return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                }
            }
        }
        output.extend(u_string::substring(&value, i32::from_ne_bytes(((copied) as i32).to_ne_bytes()), i32::from_ne_bytes(((__count7) as i32).to_ne_bytes())).encode_utf16());
        return Ok(UString::from_utf16(output.as_slice()).map_err(|_| UStringFault::UnpairedSurrogate { unit: u32::from(output[output.len() - 1]) })?);
    }

    pub(crate) fn test_trace_render_strip_whole_fraction(value: &UStr) -> Result<UString, UStringFault> {
    let __units9 = value.as_slice();
    let __count9 = u_string::unit_count(&value);
        let mut output = Vec::<u16>::new();
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count9) as i32).to_ne_bytes())) {
            if matches!(u_string::unit_at_from(__units9, index).as_ref(), Some(__v) if __v == &(46)) && (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) > (0) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units9, u32::wrapping_sub(index, 1))).as_ref().unwrap()) {
                let mut cursor = u32::wrapping_add(index, 1);
                while (i32::from_ne_bytes(((cursor) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count9) as i32).to_ne_bytes())) && matches!(u_string::unit_at_from(__units9, cursor).as_ref(), Some(__v) if __v == &(48)) {
                    cursor = u32::wrapping_add(cursor, 1);
                }
                if i32::from_ne_bytes(((cursor) as i32).to_ne_bytes()) > (i32::from_ne_bytes(((u32::wrapping_add(index, 1)) as i32).to_ne_bytes())) && (cursor == __count9 || !TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units9, cursor)).as_ref().unwrap()) && !(matches!(u_string::unit_at_from(__units9, cursor).as_ref(), Some(__v) if __v == &(46)))) {
                    index = cursor;
                    continue;
                }
            }
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !u_string::char_at_from(__units9, index).is_empty() {
                    if !match (u_string::char_at_from(__units9, index)).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            output.extend(u_string::char_at_from(__units9, index).encode_utf16());
            index = u32::wrapping_add(index, 1);
        }
        return Ok(UString::from_utf16(output.as_slice()).map_err(|_| UStringFault::UnpairedSurrogate { unit: u32::from(output[output.len() - 1]) })?);
    }

    pub(crate) fn test_trace_render_scientific_match(s: &UStr, e_index: u32, floor: u32) -> Option<Rc<RefCell<ScientificMatch>>> {
    let __units12 = s.as_slice();
    let __count12 = u_string::unit_count(&s);
        let mut i = u32::wrapping_add(e_index, 1);
        if i32::from_ne_bytes(((i) as i32).to_ne_bytes()) < (i32::from_ne_bytes(((__count12) as i32).to_ne_bytes())) && (matches!(u_string::unit_at_from(__units12, i).as_ref(), Some(__v) if __v == &(43)) || matches!(u_string::unit_at_from(__units12, i).as_ref(), Some(__v) if __v == &(45))) {
            i = u32::wrapping_add(i, 1);
        }
        let digits_start = i;
        while (i32::from_ne_bytes(((i) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count12) as i32).to_ne_bytes())) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units12, i)).as_ref().unwrap()) {
            i = u32::wrapping_add(i, 1);
        }
        if i32::from_ne_bytes(((u32::wrapping_sub(i, digits_start)) as i32).to_ne_bytes()) > (3) {
            return None;
        }
        if i == digits_start {
            return None;
        }
        let end = i;
        let exponent = TestTraceRender::test_trace_render_parse_exponent(s, u32::wrapping_add(e_index, 1), end);
        let last = u32::wrapping_sub(e_index, 1);
        if i32::from_ne_bytes(((last) as i32).to_ne_bytes()) < (i32::from_ne_bytes(((floor) as i32).to_ne_bytes())) || !TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units12, last)).as_ref().unwrap()) {
            return None;
        }
        let mut run_start = last;
        while (i32::from_ne_bytes(((run_start) as i32).to_ne_bytes())) > (i32::from_ne_bytes(((floor) as i32).to_ne_bytes())) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units12, u32::wrapping_sub(run_start, 1))).as_ref().unwrap()) {
            run_start = u32::wrapping_sub(run_start, 1);
        }
        let lead: u32;
        if i32::from_ne_bytes(((run_start) as i32).to_ne_bytes()) > (i32::from_ne_bytes(((u32::wrapping_add(floor, 1)) as i32).to_ne_bytes())) && matches!(u_string::unit_at_from(__units12, u32::wrapping_sub(run_start, 1)).as_ref(), Some(__v) if __v == &(46)) && TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units12, u32::wrapping_sub(run_start, 2))).as_ref().unwrap()) {
            lead = u32::wrapping_sub(run_start, 2);
        } else {
            if run_start != last {
                return None;
            }
            lead = last;
        }
        if i32::from_ne_bytes(((lead) as i32).to_ne_bytes()) > (0) && matches!(u_string::unit_at_from(__units12, u32::wrapping_sub(lead, 1)).as_ref(), Some(__v) if __v == &(45)) && (i32::from_ne_bytes(((u32::wrapping_sub(lead, 1)) as i32).to_ne_bytes())) >= i32::from_ne_bytes(((floor) as i32).to_ne_bytes()) {
            let before_minus = i32::from_ne_bytes(((lead) as i32).to_ne_bytes()) >= 2 && (TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units12, u32::wrapping_sub(lead, 2))).as_ref().unwrap()) || matches!(u_string::unit_at_from(__units12, u32::wrapping_sub(lead, 2)).as_ref(), Some(__v) if __v == &(46)));
            if !before_minus {
                return Some(ScientificMatch::new(u32::wrapping_sub(lead, 1), e_index, end, exponent));
            }
            return Some(ScientificMatch::new(lead, e_index, end, exponent));
        }
        let before_digit = i32::from_ne_bytes(((lead) as i32).to_ne_bytes()) > (0) && (TestTraceRender::test_trace_render_is_digit(*(u_string::unit_at_from(__units12, u32::wrapping_sub(lead, 1))).as_ref().unwrap()) || matches!(u_string::unit_at_from(__units12, u32::wrapping_sub(lead, 1)).as_ref(), Some(__v) if __v == &(46)));
        if !before_digit {
            return Some(ScientificMatch::new(lead, e_index, end, exponent));
        }
        return None;
    }

    pub(crate) fn test_trace_render_parse_exponent(s: &UStr, from: u32, to: u32) -> u32 {
    let __units14 = s.as_slice();
    let __count14 = u_string::unit_count(&s);
        let mut index = from;
        let mut negative = false;
        if i32::from_ne_bytes(((index) as i32).to_ne_bytes()) < (i32::from_ne_bytes(((to) as i32).to_ne_bytes())) && (matches!(u_string::unit_at_from(__units14, index).as_ref(), Some(__v) if __v == &(43)) || matches!(u_string::unit_at_from(__units14, index).as_ref(), Some(__v) if __v == &(45))) {
            negative = matches!(u_string::unit_at_from(__units14, index).as_ref(), Some(__v) if __v == &(45));
            index = u32::wrapping_add(index, 1);
        }
        let mut value = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((to) as i32).to_ne_bytes())) {
            value = u32::wrapping_sub(u32::wrapping_add(u32::wrapping_mul(value, 10), u_string::unit_at_from(__units14, index).unwrap_or(0)), 48);
            index = u32::wrapping_add(index, 1);
        }
        return if negative { u32::from_ne_bytes(((-(value as i32)) as u32).to_ne_bytes()) } else { value };
    }

    pub(crate) fn test_trace_render_expand_mantissa(mantissa: &UStr, exponent: u32) -> Result<UString, UStringFault> {
        let mut sign = UString::new();
        let mut value = (mantissa.to_ustring()).clone();
        if i32::from_ne_bytes(((u_string::unit_count(&(value))) as i32).to_ne_bytes()) > (0) && matches!(u_string::unit_at(&value, 0u32).as_ref(), Some(__v) if __v == &(45)) {
            sign = UString::from("-").to_ustring();
            value = u_string::substring_from(&value, 1i32);
        }
        let mut dot_index = 4294967295u32;
        let mut index = 0u32;
        let __units15 = value.as_slice();
        let __count15 = u_string::unit_count(&value);
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count15) as i32).to_ne_bytes())) {
            if matches!(u_string::unit_at_from(__units15, index).as_ref(), Some(__v) if __v == &(46)) {
                dot_index = index;
                break;
            }
            index = u32::wrapping_add(index, 1);
        }
        let mut digits = if dot_index > 2147483647 { (value.to_ustring()).clone() } else { UString::from(format!("{}", { let mut __s = UString::new(); __s += u_string::substring(&value, 0i32, i32::from_ne_bytes(((dot_index) as i32).to_ne_bytes())).as_ustr(); __s += u_string::substring_from(&value, i32::from_ne_bytes(((u32::wrapping_add(dot_index, 1)) as i32).to_ne_bytes())).as_ustr(); __s }).as_str()) };
        while (i32::from_ne_bytes(((u_string::unit_count(&(digits))) as i32).to_ne_bytes())) > (1) && matches!(u_string::unit_at(&digits, u32::wrapping_sub(u_string::unit_count(&(digits)), 1)).as_ref(), Some(__v) if __v == &(48)) {
            digits = u_string::substring(&digits, 0i32, i32::from_ne_bytes(((u32::wrapping_sub(u_string::unit_count(&(digits)), 1)) as i32).to_ne_bytes()));
        }
        if i32::from_ne_bytes(((exponent) as i32).to_ne_bytes()) > (400) || (i32::from_ne_bytes(((exponent) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((4294966896u32) as i32).to_ne_bytes())) {
            return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += sign.as_ustr(); __s += value.as_ustr(); __s }).as_str()));
        }
        let decimal_position = i32::wrapping_add(i32::from_ne_bytes(((if dot_index > 2147483647 { u_string::unit_count(&(value)) } else { dot_index }) as i32).to_ne_bytes()), i32::from_ne_bytes(((exponent) as i32).to_ne_bytes()));
        if decimal_position <= 0 {
            return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += sign.as_ustr(); __s += &(UString::from("0.")); __s += TestTraceRender::test_trace_render_zeroes(u32::from_ne_bytes(((-(decimal_position as i32)) as u32).to_ne_bytes()))?.as_ustr(); __s += digits.as_ustr(); __s }).as_str()));
        }
        if decimal_position >= i32::from_ne_bytes(((u_string::unit_count(&(digits))) as i32).to_ne_bytes()) {
            return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += sign.as_ustr(); __s += digits.as_ustr(); __s += TestTraceRender::test_trace_render_zeroes(u32::from_ne_bytes(((i32::wrapping_sub(decimal_position, i32::from_ne_bytes(((u_string::unit_count(&(digits))) as i32).to_ne_bytes()))) as u32).to_ne_bytes()))?.as_ustr(); __s }).as_str()));
        }
        return Ok(UString::from(format!("{}", { let mut __s = UString::new(); __s += sign.as_ustr(); __s += u_string::substring(&digits, 0i32, i32::from_ne_bytes(((decimal_position) as i32).to_ne_bytes())).as_ustr(); __s += &(UString::from(".")); __s += u_string::substring_from(&digits, i32::from_ne_bytes(((decimal_position) as i32).to_ne_bytes())).as_ustr(); __s }).as_str()));
    }

    pub(crate) fn test_trace_render_zeroes(count: u32) -> Result<UString, UStringFault> {
        let mut output = Vec::<u16>::new();
        for _ in 0..count {
            if let Some(&unit) = output.last() {
                if unit >= 55296 && unit <= 56319 && !UString::from("0").is_empty() {
                    if !match (UString::from("0")).encode_utf16().next() { Some(head) => head >= 56320 && head <= 57343, None => false } {
                        return Err(UStringFault::UnpairedSurrogate { unit: u32::from(unit) });
                    }
                }
            }
            output.extend(UString::from("0").encode_utf16());
        }
        return Ok(UString::from_utf16(output.as_slice()).map_err(|_| UStringFault::UnpairedSurrogate { unit: u32::from(output[output.len() - 1]) })?);
    }

    pub(crate) fn test_trace_render_is_digit(code_unit: u32) -> bool {
        return (i32::from_ne_bytes(((code_unit) as i32).to_ne_bytes())) >= 48 && (i32::from_ne_bytes(((code_unit) as i32).to_ne_bytes())) <= 57;
    }

    pub(crate) fn test_trace_render_fnv1a(value: &UStr) -> UString {
    let __units16 = value.as_slice();
    let __count16 = u_string::unit_count(&value);
        let mut hash = 2166136261u32;
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count16) as i32).to_ne_bytes())) {
            hash = hash ^ u_string::unit_at_from(__units16, index).unwrap_or(0);
            hash = TestTraceRender::test_trace_render_multiply_fnv_prime(hash);
            index = u32::wrapping_add(index, 1);
        }
        let first = u32::from(hash.to_be_bytes()[0]);
        let second = u32::from(hash.to_be_bytes()[1]);
        let third = u32::from(hash.to_be_bytes()[2]);
        let fourth = u32::from(hash.to_be_bytes()[3]);
        let mut output = { let mut __s = UString::new(); __s += TestTraceRender::test_trace_render_hex_byte(first).as_ustr(); __s += TestTraceRender::test_trace_render_hex_byte(second).as_ustr(); __s += TestTraceRender::test_trace_render_hex_byte(third).as_ustr(); __s += TestTraceRender::test_trace_render_hex_byte(fourth).as_ustr(); __s };
        while (i32::from_ne_bytes(((u_string::unit_count(&(output))) as i32).to_ne_bytes())) > (1) && matches!(u_string::unit_at(&output, 0u32).as_ref(), Some(__v) if __v == &(48)) {
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

    pub(crate) fn test_trace_render_hex_byte(value: u32) -> UString {
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += u_string::substring(&TestTraceRender::TEST_TRACE_RENDER_HEX.to_ustring(), i32::from_ne_bytes(((value >> 4 & 15) as i32).to_ne_bytes()), i32::from_ne_bytes(((u32::wrapping_add(value >> 4 & 15, 1)) as i32).to_ne_bytes())).as_ustr(); __s += u_string::substring(&TestTraceRender::TEST_TRACE_RENDER_HEX.to_ustring(), i32::from_ne_bytes(((value & 15) as i32).to_ne_bytes()), i32::from_ne_bytes(((u32::wrapping_add(value & 15, 1)) as i32).to_ne_bytes())).as_ustr(); __s }).as_str());
    }
}

#[derive(Clone, PartialEq)]
pub struct DecimalShape {
    pub digits: UString,
    pub position: u32,
    pub extended: bool,
}

impl DecimalShape {
    pub fn new(digits: &UStr, position: u32, extended: bool) -> Rc<RefCell<Self>> {
        Rc::new(RefCell::new(Self {
            digits: digits.to_ustring(),
            position,
            extended,
        }))
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
    pub fn new(start: u32, mantissa_end: u32, end: u32, exponent: u32) -> Rc<RefCell<Self>> {
        Rc::new(RefCell::new(Self {
            start,
            mantissa_end,
            end,
            exponent,
        }))
    }
}
