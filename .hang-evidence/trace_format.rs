use crate::runtime::fp_helper::FPHelper;
use crate::runtime::u_string;
use crate::runtime::u_string::UStr;
use crate::runtime::u_string::UString;


#[derive(Clone, Copy)]
pub struct TraceFormat;

impl TraceFormat {
    pub fn trace_format_i(value: u32) -> UString {
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("")); __s += &(UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(value)).as_str())); __s }).as_str());
    }

    pub fn trace_format_f(value: f64) -> UString {
        let rounded = TraceFormat::trace_format_f32_mirror(value);
        if rounded != rounded {
            return UString::from("NaN").to_ustring();
        }
        if rounded == f64::INFINITY {
            return UString::from("Infinity").to_ustring();
        }
        if rounded == f64::NEG_INFINITY {
            return UString::from("-Infinity").to_ustring();
        }
        return TraceFormat::trace_format_fixed_decimal_text(rounded, 1);
    }

    pub fn trace_format_fd(value: f64, decimals: u32) -> UString {
        let rounded = TraceFormat::trace_format_f32_mirror(value);
        if rounded != rounded {
            return UString::from("NaN").to_ustring();
        }
        if rounded == f64::INFINITY {
            return UString::from("Infinity").to_ustring();
        }
        if rounded == f64::NEG_INFINITY {
            return UString::from("-Infinity").to_ustring();
        }
        return TraceFormat::trace_format_fixed_decimal_text(rounded, decimals);
    }

    pub fn trace_format_d(value: f64) -> UString {
        if value != value {
            return UString::from("NaN").to_ustring();
        }
        if value == f64::INFINITY {
            return UString::from("Infinity").to_ustring();
        }
        if value == f64::NEG_INFINITY {
            return UString::from("-Infinity").to_ustring();
        }
        return TraceFormat::trace_format_fixed_decimal_text(value, 1);
    }

    pub fn trace_format_value_string(value: &UStr) -> UString {
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("'")); __s += TraceFormat::trace_format_escape_text(value).as_ustr(); __s += &(UString::from("'")); __s }).as_str());
    }

    pub fn trace_format_value_int(value: u32) -> UString {
        return TraceFormat::trace_format_i(value);
    }

    pub fn trace_format_value_long(value: u32) -> UString {
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("")); __s += &(UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(value)).as_str())); __s }).as_str());
    }

    pub fn trace_format_value_float(value: f64) -> UString {
        return TraceFormat::trace_format_fd(value, 1);
    }

    pub fn trace_format_value_double(value: f64) -> UString {
        return TraceFormat::trace_format_d(value);
    }

    pub fn trace_format_value_bool(value: bool) -> UString {
        return if value { UString::from("true") } else { UString::from("false") };
    }

    pub fn trace_format_value_null() -> UString {
        return UString::from("-").to_ustring();
    }

    pub fn trace_format_escape_text(value: &UStr) -> UString {
    let __units = value.as_slice();
    let __count = u_string::unit_count(&value);
        let mut output = UString::new();
        let mut index = 0u32;
        while (i32::from_ne_bytes(((index) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((__count) as i32).to_ne_bytes())) {
            let code_unit = u_string::unit_at_from(__units, index).unwrap_or(0);
            if code_unit == 10 {
                output += &(UString::from("\\n"));
            } else {
                if code_unit == 13 {
                    output += &(UString::from("\\r"));
                } else {
                    if code_unit == 11 {
                        output += &(UString::from("\\v"));
                    } else {
                        if code_unit == 12 {
                            output += &(UString::from("\\f"));
                        } else {
                            if code_unit == 133 {
                                output += &(UString::from("\\u0085"));
                            } else {
                                if code_unit == 8232 {
                                    output += &(UString::from("\\u2028"));
                                } else {
                                    if code_unit == 8233 {
                                        output += &(UString::from("\\u2029"));
                                    } else {
                                        if code_unit == 8203 {
                                            output += &(UString::from("\\u200B"));
                                        } else {
                                            output += &(u_string::char_at_from(__units, index));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            index = u32::wrapping_add(index, 1);
        }
        return output;
    }

    pub(crate) fn trace_format_fixed_decimal_text(value: f64, decimals: u32) -> UString {
        let negative = TraceFormat::trace_format_is_negative(value);
        let magnitude = (value).abs();
        if magnitude != magnitude {
            return UString::from("NaN").to_ustring();
        }
        if magnitude >= 2147483648.0f64 {
            return UString::from(format!("{}", crate::runtime::fp_helper::FPHelper::format_float(value)).as_str());
        }
        let scale = TraceFormat::trace_format_pow10(decimals);
        let rounded = TraceFormat::trace_format_scaled_magnitude(magnitude, scale);
        let integer_part = TraceFormat::trace_format_integer_part_of(magnitude, rounded, scale);
        let fraction_part = u32::try_from((rounded.wrapping_sub(TraceFormat::trace_format_multiply(integer_part, scale))) & 0xFFFF_FFFF).unwrap_or(0);
        let mut fraction_text = { let mut __s = UString::new(); __s += &(UString::from("")); __s += &(UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(fraction_part)).as_str())); __s };
        while (i32::from_ne_bytes(((u_string::unit_count(&(fraction_text))) as i32).to_ne_bytes())) < (i32::from_ne_bytes(((decimals) as i32).to_ne_bytes())) {
            fraction_text = UString::from(format!("{}", { let mut __s = UString::new(); __s += &(UString::from("0")); __s += fraction_text.as_ustr(); __s }).as_str());
        }
        return UString::from(format!("{}", { let mut __s = UString::new(); __s += (if negative { UString::from("-") } else { UString::from("") }).as_ustr(); __s += &(UString::from(format!("{}", crate::runtime::int_text::IntText::int_text(integer_part)).as_str())); __s += &(UString::from(".")); __s += fraction_text.as_ustr(); __s }).as_str());
    }

    pub(crate) fn trace_format_is_negative(value: f64) -> bool {
        return (value) < (0 as f64) || value == 0 as f64 && (format!("{}", (1i32)).parse::<f64>().unwrap_or(0.0) / value) < (0 as f64);
    }

    pub(crate) fn trace_format_pow10(decimals: u32) -> u32 {
        let mut scale = 1u32;
        for _ in 0..decimals {
            scale = u32::wrapping_mul(scale, 10);
        }
        return scale;
    }

    pub(crate) fn trace_format_scaled_magnitude(magnitude: f64, scale: u32) -> i64 {
        let bits = FPHelper::float_to_i32(magnitude);
        let exponent_field = bits >> 23 & 255;
        let mantissa_bits = bits & 8388607;
        let mantissa = if u32::from_ne_bytes(((exponent_field) as u32).to_ne_bytes()) == 0 { u32::from_ne_bytes(((mantissa_bits) as u32).to_ne_bytes()) } else { u32::from_ne_bytes(((u32::from_ne_bytes(((mantissa_bits) as u32).to_ne_bytes()) | 8388608) as u32).to_ne_bytes()) };
        let exponent = if u32::from_ne_bytes(((exponent_field) as u32).to_ne_bytes()) == 0 { 4294967147u32 } else { u32::from_ne_bytes(((i32::wrapping_sub(exponent_field, 150)) as u32).to_ne_bytes()) };
        let product = TraceFormat::trace_format_multiply(mantissa, scale);
        if exponent <= 2147483647 {
            return product.wrapping_shl(exponent);
        }
        let divisor_shift = -(exponent as i32);
        if divisor_shift >= 64 {
            return 0i64;
        }
        return i64::from_ne_bytes(u64::from_ne_bytes((product.wrapping_add((1i64).wrapping_shl(u32::from_ne_bytes(((i32::wrapping_sub(divisor_shift, 1)) as u32).to_ne_bytes())))).to_ne_bytes()).wrapping_shr(u32::from_ne_bytes(((divisor_shift) as u32).to_ne_bytes())).to_ne_bytes());
    }

    pub(crate) fn trace_format_integer_part_of(magnitude: f64, rounded: i64, scale: u32) -> u32 {
        let mut whole = u32::from_ne_bytes(((match f64::from(f64::floor(magnitude)) { v if v.is_nan() => 0i32, v if v >= 2147483648.0 => 2147483647i32, v if v < -2147483648.0 => -2147483648i32, v if v < 0.0 => i32::from_ne_bytes(u32::wrapping_sub(0, match ((0.0 - v).to_bits() >> 52) & 2047 { e if e < 1023 => 0u32, e => u32::try_from((((0.0 - v).to_bits() & 4503599627370495) | 4503599627370496) >> (52 - (e - 1023))).unwrap_or(0) }).to_ne_bytes()), v => i32::from_ne_bytes(match ((v).to_bits() >> 52) & 2047 { e if e < 1023 => 0u32, e => u32::try_from((((v).to_bits() & 4503599627370495) | 4503599627370496) >> (52 - (e - 1023))).unwrap_or(0) }.to_ne_bytes()) }) as u32).to_ne_bytes());
        if rounded >= TraceFormat::trace_format_multiply(u32::wrapping_add(whole, 1), scale) {
            whole = u32::wrapping_add(whole, 1);
        }
        return whole;
    }

    pub(crate) fn trace_format_multiply(left: u32, right: u32) -> i64 {
        let mut product = 0i64;
        let mut factor = right;
        let mut shift = 0u32;
        while (i32::from_ne_bytes(((factor) as i32).to_ne_bytes())) > (0) {
            if factor & 1 != 0 {
                product = product.wrapping_add((i64::from((left) ^ 0x8000_0000u32).wrapping_sub(0x8000_0000i64)).wrapping_shl(shift));
            }
            factor = factor >> 1;
            shift = u32::wrapping_add(shift, 1);
        }
        return product;
    }

    pub(crate) fn trace_format_f32_mirror(value: f64) -> f64 {
        return FPHelper::i32_to_float(FPHelper::float_to_i32(value));
    }
}
