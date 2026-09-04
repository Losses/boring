package rustcompiler;

#if (macro || reflaxe_runtime)
/**
	Zero-`as` numeric conversion helpers for the rust emitter.

	Every function replaces a specific `as` cast family with a bit-level
	equivalent, so the generated crate compiles without any numeric `as`.
	Each helper documents the cast it replaces, the bit-level equivalence,
	and why any `unwrap_or` dead arm is unreachable.

	Parenthesization: each helper returns a self-contained expression that
	binds at least as tightly as the `(x) as T` form it replaces, so a caller
	can interpolate the result wherever the old cast stood without changing
	operator precedence. The operand `x` is always wrapped in parentheses so
	its own precedence cannot leak into the surrounding cast-free expression.

	No standard-library detail below is guessed: the `unsafe`-free integer
	`from` / `from_ne_bytes` / `try_from` forms and their masks were verified
	against the current `as` output by the dispatch probes (aszero-probe2/3/4).
**/
class RustConversions {
	/**
		T2 lossless widening via `std::convert::From`.
		Replaces `(x) as i64` (x: u32), `(x) as u64` (x: u32), and
		`(x) as u32` (x: u16). `std` implements `From<u32> for i64/u64` and
		`From<u16> for u32`, so the value is preserved exactly. There is no
		`usize::from(u32)` in `std`, so index sites must use indexUsize
		instead of this helper.
	**/
	public static function widen(x: String, to: String): String {
		return to + "::from(" + x + ")";
	}

	/**
		T3 index widening for `arr[(i) as usize]` with `i` a Haxe Int (u32).
		Replaces `(i) as usize` with `usize::try_from(i).unwrap_or(0)`. On a
		u32 source, `usize::try_from` succeeds for every value on 32-bit and
		64-bit targets, so the `unwrap_or(0)` arm is unreachable; the 0 keeps
		the emission non-fallible without ever evaluating on a real failure.
	**/
	public static function indexUsize(x: String): String {
		return "usize::try_from(" + x + ").unwrap_or(0)";
	}

	/**
		T4 truncating narrowing via mask-then-`try_from`. Replaces
		`(x) as u32` (x: usize/i64), `(x) as u16` (x: Int→u16), and
		`(x) as u8` (x: Int→u8). The mask first reduces `x` into the target's
		bit width, so `try_from` always succeeds and the `unwrap_or(0)` arm is
		unreachable. Masking the low bits is exactly the value a Rust `as`
		truncating cast keeps, verified by the probes for a usize above
		u32::MAX, `i64::MIN`, and negative values.
	**/
	public static function truncate(x: String, to: String): String {
		final mask = switch(to) {
			case "u32": "0xFFFF_FFFF";
			case "u16": "0xFFFF";
			case "u8": "0xFF";
			default: failTarget(to);
		};
		return to + "::try_from((" + x + ") & " + mask + ").unwrap_or(0)";
	}

	/**
		T5 same-width bit reinterpretation. Replaces `(x) as i32` (x: u32),
		`(x) as u32` (x: i32), `(x) as i64` (x: u64), and `(x) as u64`
		(x: i64) with a native-endian byte round-trip. `as` on same-width
		integer types reinterprets the bits; `try_from` would be a value
		conversion and overflow, so reinterpretation must never use it.
	**/
	public static function reinterpret(x: String, to: String): String {
		// The `from_ne_bytes` call parentheses delimit the argument; drop a
		// redundant outer grouping from a compound rendered source so the
		// generated code stays free of unnecessary-parens warnings.
		var inner = x;
		if(StringTools.startsWith(inner, "(") && StringTools.endsWith(inner, ")")) {
			var depth = 0;
			var balanced = true;
			for(i in 0...inner.length) {
				final c = inner.charAt(i);
				if(c == "(") depth++;
				else if(c == ")") {
					depth--;
					if(depth == 0 && i < inner.length - 1) { balanced = false; break; }
				}
			}
			if(balanced && depth == 0) inner = inner.substr(1, inner.length - 2);
		}
		return to + "::from_ne_bytes((" + inner + ").to_ne_bytes())";
	}

	/**
		T6 `Int64.ofInt` sign extension from the u32 domain. Replaces
		`(x as i32) as i64` where x is the u32 rendering of an Int to be
		sign-extended. XORing the sign bit maps the whole u32 onto the
		non-negative half of i64, then `wrapping_sub` flips it back; together
		the two steps are the value of a signed 32-bit two's-complement
		extension, verified for 0, 0x7FFFFFFF, 0x80000000 and 0xFFFFFFFF.
	**/
	public static function ofInt(x: String): String {
		return "i64::from((" + x + ") ^ 0x8000_0000u32).wrapping_sub(0x8000_0000i64)";
	}

	/**
		T7 int-to-float via exact decimal parse. Replaces `(x) as f64`
		(x: u32/i32) and `(x) as f32` (x: u32/i32). An integer's `Display`
		is its exact decimal form and `parse` performs correctly-rounded
		conversion, matching the `as` result for every representable value.
		The `unwrap_or(0.0)` arm cannot fire because the decimal of any
		integer is always parseable.
	**/
	public static function intToFloat(x: String, real: String): String {
		return "format!(\"{}\", (" + x + ")).parse::<" + real + ">().unwrap_or(0.0)";
	}

	/**
		Float to u32 with Rust's `as u32` saturation, without an `as` cast.
		Replaces `(x) as u32` (x: f64/f32) where a Haxe Int truncates a
		Float: Rust `as` saturates at the domain ends and zeroes NaN and
		negative values. The value side splits the exponent and shifts the
		implicit-bit mantissa down by the fraction width; the guard branches
		reproduce the saturation exactly. The input widens through `f64::from`
		(identity for a binary64 value, exact for binary32) so one 64-bit
		bit decomposition serves both real widths. The shift only runs for
		finite non-negative inputs below 2^32 (exponent 0..31), where the
		shift amount stays in range.
	**/
	public static function floatToU32(x: String): String {
		return "match f64::from(" + x + ") { v if !(v >= 0.0) || v.is_nan() => 0u32, v if v >= 4294967296.0 => 4294967295u32, v => "
			+ truncU32Inner("v") + " }";
	}

	/**
		Float to i32 with Rust's `as i32` saturation, without an `as` cast.
		NaN zeroes; the domain ends saturate; an in-range negative value
		keeps its sign through two's-complement wrapping of the magnitude's
		truncation; a non-negative value reinterprets its truncation bits.
	**/
	public static function floatToI32(x: String): String {
		return "match f64::from(" + x + ") { v if v.is_nan() => 0i32, v if v >= 2147483648.0 => 2147483647i32, v if v < -2147483648.0 => -2147483648i32, "
			+ "v if v < 0.0 => i32::from_ne_bytes(u32::wrapping_sub(0, " + truncU32Inner("(0.0 - v)") + ").to_ne_bytes()), "
			+ "v => i32::from_ne_bytes(" + truncU32Inner("v") + ".to_ne_bytes()) }";
	}

	/** Truncation of a finite non-negative float below 2^32 to its u32 value. */
	static function truncU32Inner(v: String): String {
		return "match ((" + v + ").to_bits() >> 52) & 2047 { e if e < 1023 => 0u32, "
			+ "e => u32::try_from((((" + v + ").to_bits() & 4503599627370495) | 4503599627370496) >> (52 - (e - 1023))).unwrap_or(0) }";
	}

	/**
		T8 i64 logical right shift without unsigned casts. Replaces
		`((x) as u64).wrapping_shr(n) as i64` with a byte round-trip: the bits
		are interpreted as u64, shifted logically, and reinterpreted as i64.
		Same-width reinterpretation makes this identical to the current
		u64-cast shift for every x and shift n in 0..63.
	**/
	public static function shrLogicalI64(x: String, n: String): String {
		return "i64::from_ne_bytes(u64::from_ne_bytes((" + x + ").to_ne_bytes()).wrapping_shr(" + n + ").to_ne_bytes())";
	}

	/**
		Narrowing a usize value to a signed i32 the way `(x) as i32` does:
		keep the low 32 bits and reinterpret them as two's-complement signed.
		The byte round-trip reads the native-endian low word, so it equals
		`as` for every usize (verified by aszero-probe5 for 0, u32::MAX, and a
		usize above u32::MAX, which truncates to 1).
	**/
	public static function narrowI32(x: String): String {
		return "i32::from_ne_bytes(u32::from_ne_bytes((" + x + ").to_ne_bytes()[..4].try_into().unwrap()).to_ne_bytes())";
	}

	static function failTarget(to: String): String {
		return "0xFFFF_FFFF";
	}
}
#end