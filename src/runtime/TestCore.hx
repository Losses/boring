package runtime;

import std.TestPlatform;
import std.UStringPlatform;

/**
	Assertion checks and canonical failure formatting, the single source
	behind the per-target test hosts
	(docs/specs/features/19-testing.md). Each target compiles
	this class into its test runtime package beside the host entry; the
	hosts keep only the state the runner tracks, the raising behavior of
	their language, and the result-file edge.

	Every parameter is a plain non-null value: absent messages arrive as
	the empty string, which the canonical builder treats as omitted, the
	same rule the previous hosts applied to null and empty alike. The
	std.TestPlatform calls lower inline per target; std.UStringPlatform
	carries the code-point walk of escapeJson, so the escaping is
	byte-correct on every target.
**/
class TestCore {
	/** Fail unless `condition` holds; `message` may be empty. */
	public static function ok(condition:Bool, message:String):Void {
		if(!condition) {
			TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, "", "", false));
		}
	}

	/** Fail unconditionally with `message`. */
	public static function fail(message:String):Void {
		TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, "", "", false));
	}

	/** Fail unless both booleans are equal. */
	public static function equalsBool(expected:Bool, actual:Bool, message:String):Void {
		if(expected != actual) {
			TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, formatBool(expected), formatBool(actual), true));
		}
	}

	/** Fail unless both integers are equal. */
	public static function equalsInt(expected:Int, actual:Int, message:String):Void {
		if(expected != actual) {
			TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, formatInt(expected), formatInt(actual), true));
		}
	}

	/**
		Fail unless both floats are equal under IEEE semantics: NaN never
		equals itself, so expecting NaN always fails.
	**/
	public static function equalsFloat(expected:Float, actual:Float, message:String):Void {
		if(expected != actual) {
			TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, formatFloat(expected), formatFloat(actual), true));
		}
	}

	/** Fail unless both strings are equal. */
	public static function equalsString(expected:String, actual:String, message:String):Void {
		if(expected != actual) {
			TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, formatString(expected), formatString(actual), true));
		}
	}

	/** Raise the canonical failure text for a mismatch already described. */
	public static function reportFailure(message:String, expectedStr:String, actualStr:String):Void {
		TestPlatform.raise(formatCanonicalMessage(TestPlatform.currentTestId(), message, expectedStr, actualStr, true));
	}

	/** The canonical text of a boolean. */
	public static function formatBool(v:Bool):String {
		if(v) {
			return "true";
		}
		return "false";
	}

	/** The canonical text of an integer. */
	public static function formatInt(v:Int):String {
		return TestPlatform.intToString(v);
	}

	/**
		The canonical text of a float: the special values carry names, a
		zero of either sign renders as "0", and a whole number drops the
		".0" fraction some targets append.
	**/
	public static function formatFloat(v:Float):String {
		// NaN is the only float not equal to itself.
		if(v != v) {
			return "NaN";
		}
		if(v == Math.POSITIVE_INFINITY) {
			return "Infinity";
		}
		if(v == Math.NEGATIVE_INFINITY) {
			return "-Infinity";
		}
		if(v == 0.0) {
			return "0";
		}
		final raw = TestPlatform.floatToString(v);
		var s = raw;
		var negative = false;
		if(s.charCodeAt(0) == 45) {
			negative = true;
			s = s.substring(1);
		}
		final exponentParts = s.split("e");
		var exponent = 0;
		if(exponentParts.length == 2) {
			final exponentText = exponentParts[1];
			final exponentValue = Std.parseInt(exponentText);
			exponent = exponentValue == null ? 0 : exponentValue;
			s = exponentParts[0];
		}
		final decimalParts = s.split(".");
		final hasDot = decimalParts.length == 2;
		var fraction = "";
		if(hasDot) fraction = decimalParts[1];
		var digits = decimalParts[0] + fraction;
		var decimalPosition = decimalParts[0].length + exponent;
		while(digits.length > 1 && digits.charCodeAt(0) == 48) {
			digits = digits.substring(1);
			decimalPosition -= 1;
		}
		if(digits == "0") return "0";
		if(decimalPosition >= -5 && decimalPosition <= 21) {
			var plain = decimalPosition <= 0 ? plainLeading(digits, decimalPosition)
				: decimalPosition >= digits.length ? plainTrailing(digits, decimalPosition)
				: digits.substring(0, decimalPosition) + "." + digits.substring(decimalPosition);
			while(plain.length > 0 && plain.charCodeAt(plain.length - 1) == 48 && plain.split(".").length > 1) plain = plain.substring(0, plain.length - 1);
			if(plain.length > 0 && plain.charCodeAt(plain.length - 1) == 46) plain = plain.substring(0, plain.length - 1);
			return (negative ? "-" : "") + plain;
		}
		while(digits.length > 1 && digits.charCodeAt(digits.length - 1) == 48) digits = digits.substring(0, digits.length - 1);
		final sciExponent = decimalPosition - 1;
		final mantissa = digits.length == 1 ? digits : digits.substring(0, 1) + "." + digits.substring(1);
		return (negative ? "-" : "") + mantissa + "e" + (sciExponent >= 0 ? "+" : "") + sciExponent;
	}

	/** The plain spelling below one: zeros between the point and the digits. */
	static function plainLeading(digits:String, decimalPosition:Int):String {
		var head = "0.";
		for(_ in 0...-decimalPosition) head += "0";
		return head + digits;
	}

	/** The plain spelling past the last digit: zeros after the digits. */
	static function plainTrailing(digits:String, decimalPosition:Int):String {
		var tail = "";
		for(_ in 0...decimalPosition - digits.length) tail += "0";
		return digits + tail;
	}

	/** The canonical text of a string: quoted, with JSON escaping inside. */
	public static function formatString(v:String):String {
		return "\"" + escapeJson(v) + "\"";
	}

	/** The canonical text of a byte sequence: lowercase hex digits. */
	public static function formatBytes(b:haxe.io.Bytes):String {
		var out = "";
		for(index in 0...b.length) {
			final value = b.get(index);
			out += hexDigit((value >> 4) & 0xF);
			out += hexDigit(value & 0xF);
		}
		return out;
	}

	/**
		The JSON string escaping of the result records: the two quoted
		specials, the four short escapes, and \\u plus four lowercase hex
		digits below 0x20; every other code point passes through whole.
	**/
	public static function escapeJson(s:String):String {
		var out = "";
		var cursor = 0;
		final stop = UStringPlatform.end(s);
		while(cursor < stop) {
			final code = UStringPlatform.codeAt(s, cursor);
			if(code == 0x22) {
				out += "\\\"";
			} else if(code == 0x5C) {
				out += "\\\\";
			} else if(code == 0x0A) {
				out += "\\n";
			} else if(code == 0x0D) {
				out += "\\r";
			} else if(code == 0x09) {
				out += "\\t";
			} else if(code < 0x20) {
				out += "\\u" + hexDigit((code >> 12) & 0xF) + hexDigit((code >> 8) & 0xF) + hexDigit((code >> 4) & 0xF) + hexDigit(code & 0xF);
			} else {
				out += UStringPlatform.substringBetween(s, cursor, UStringPlatform.advance(s, cursor));
			}
			cursor = UStringPlatform.advance(s, cursor);
		}
		return out;
	}

	/**
		The canonical failure text: the test id line, the message line
		when a non-empty message exists, and the expected and actual lines
		of an equality check.
	**/
	public static function formatCanonicalMessage(id:String, message:String, expectedStr:String, actualStr:String, isEquals:Bool):String {
		var out = "test failed: " + id;
		if(message != "") {
			out += "\n  message: " + message;
		}
		if(isEquals) {
			out += "\n  expected: " + expectedStr;
			out += "\n  actual:   " + actualStr;
		}
		return out;
	}

	/** One JSON line of the result record, newline included. */
	public static function resultLine(id:String, name:String, failed:Bool, message:String):String {
		if(failed) {
			return '{"id":"' + escapeJson(id) + '","name":"' + escapeJson(name) + '","verdict":"fail","message":"' + escapeJson(message) + '"}\n';
		}
		return '{"id":"' + escapeJson(id) + '","name":"' + escapeJson(name) + '","verdict":"pass"}\n';
	}

	/** The lowercase hex digit of a value below sixteen. */
	static function hexDigit(nibble:Int):String {
		if(nibble < 10) {
			return UStringPlatform.fromCodePoint(48 + nibble);
		}
		return UStringPlatform.fromCodePoint(87 + nibble);
	}
}
