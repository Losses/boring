use crate::runtime::u_string::UString;

pub struct FPHelper;

pub struct Int64Halves {
    pub high: u32,
    pub low: u32,
}

impl FPHelper {
    pub fn format_float(v: f64) -> UString {
        if v.is_nan() { return UString::from("NaN"); }
        if v == f64::INFINITY { return UString::from("Infinity"); }
        if v == f64::NEG_INFINITY { return UString::from("-Infinity"); }
        UString::from(Self::format_float_text(v.to_string()).as_str())
    }

    pub fn format_float_f32(v: f32) -> UString {
        if v.is_nan() { return UString::from("NaN"); }
        if v == f32::INFINITY { return UString::from("Infinity"); }
        if v == f32::NEG_INFINITY { return UString::from("-Infinity"); }
        UString::from(Self::format_float_text(v.to_string()).as_str())
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

    // The two 64-bit FPHelper value edges carry the binary32 bit pattern,
    // like every other backend: floatToI32 reads the f32 bit pattern
    // instead of truncating toward zero, and i32ToFloat reinterprets
    // the i32 as raw binary32 bits instead of widening numerically
    // (feature spec 23; FpText round-trips compare bit patterns).
    pub fn float_to_i32(v: f64) -> i32 {
        (v as f32).to_bits() as i32
    }

    pub fn i32_to_float(v: i32) -> f64 {
        f32::from_bits(v as u32) as f64
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
            if high & 1048575 == 0 && low == 0 {
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
