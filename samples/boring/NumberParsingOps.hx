package boring;

class NumberParsingOps {
	public static function parseFloat(value:String):Float {
		#if boring_oracle
		return NumberParsingOracle.parseFloat(value);
		#else
		return Std.parseFloat(value);
		#end
	}
	public static function parseInt(value:String):Null<Int> {
		#if boring_oracle
		return NumberParsingOracle.parseInt(value);
		#else
		return Std.parseInt(value);
		#end
	}
	public static function failedFloat(value:String):Bool {
		#if boring_oracle
		return Math.isNaN(parseFloat(value));
		#else
		return Math.isNaN(Std.parseFloat(value));
		#end
	}
	public static function failedInt(value:String):Bool {
		#if boring_oracle
		return parseInt(value) == null;
		#else
		return Std.parseInt(value) == null;
		#end
	}
}

#if boring_oracle
/**
 * Stage-1 oracle for the complete-token parsing contract of spec 14.
 * Plain haxe parses a leading token on the reference run, while the
 * generated lanes lower Std.parseFloat and Std.parseInt to guarded
 * native conversions. The oracle applies the whole-token grammar so the
 * in-source tests observe the ruled failure results on both sides.
 */
class NumberParsingOracle {
	public static function parseFloat(value:String):Float {
		final token = StringTools.trim(value);
		return validFloatToken(token) ? Std.parseFloat(token) : Math.NaN;
	}

	public static function parseInt(value:String):Null<Int> {
		final token = StringTools.trim(value);
		if (decimalIntToken(token)) {
			final parsed = Std.parseInt(token);
			return parsed != null && parsed >= -2147483648 && parsed <= 2147483647 ? parsed : null;
		}
		if (hexIntToken(token)) {
			final negative = token.charAt(0) == "-";
			final unsigned = negative || token.charAt(0) == "+" ? token.substring(1) : token;
			final magnitude = Std.parseInt("0" + unsigned.substring(1));
			final signed = negative ? -magnitude : magnitude;
			return signed >= -2147483648 && signed <= 2147483647 ? signed : null;
		}
		return null;
	}

	static function validFloatToken(token:String):Bool {
		var index = 0;
		if (index < token.length && (token.charAt(index) == "+" || token.charAt(index) == "-")) index++;
		var mantissaDigits = 0;
		while (index < token.length && isDigitAt(token, index)) {
			index++;
			mantissaDigits++;
		}
		if (index < token.length && token.charAt(index) == ".") {
			index++;
			while (index < token.length && isDigitAt(token, index)) {
				index++;
				mantissaDigits++;
			}
		}
		if (mantissaDigits == 0) return false;
		if (index < token.length && (token.charAt(index) == "e" || token.charAt(index) == "E")) {
			index++;
			if (index < token.length && (token.charAt(index) == "+" || token.charAt(index) == "-")) index++;
			var exponentDigits = 0;
			while (index < token.length && isDigitAt(token, index)) {
				index++;
				exponentDigits++;
			}
			if (exponentDigits == 0) return false;
		}
		return index == token.length;
	}

	static function decimalIntToken(token:String):Bool {
		var index = 0;
		if (index < token.length && (token.charAt(index) == "+" || token.charAt(index) == "-")) index++;
		var digits = 0;
		while (index < token.length && isDigitAt(token, index)) {
			index++;
			digits++;
		}
		return digits > 0 && index == token.length;
	}

	static function hexIntToken(token:String):Bool {
		var index = 0;
		if (index < token.length && (token.charAt(index) == "+" || token.charAt(index) == "-")) index++;
		if (index + 1 >= token.length || token.charAt(index) != "0") return false;
		final marker = token.charAt(index + 1);
		if (marker != "x" && marker != "X") return false;
		index += 2;
		var digits = 0;
		while (index < token.length && isHexDigitAt(token, index)) {
			index++;
			digits++;
		}
		return digits > 0 && index == token.length;
	}

	static function isDigitAt(token:String, index:Int):Bool {
		final code = token.charCodeAt(index);
		return code != null && code >= 0x30 && code <= 0x39;
	}

	static function isHexDigitAt(token:String, index:Int):Bool {
		final code = token.charCodeAt(index);
		return code != null
			&& ((code >= 0x30 && code <= 0x39)
				|| (code >= 0x41 && code <= 0x46)
				|| (code >= 0x61 && code <= 0x66));
	}
}
#end
