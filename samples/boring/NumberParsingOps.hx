package boring;

class NumberParsingOps {
#if boring_oracle
	private static function isTrim(code:Int):Bool {
		return code == 32 || code == 9 || code == 10 || code == 11 || code == 12 || code == 13;
	}

	private static function trim(value:String):String {
		var start = 0;
		var end = value.length;
		while (start < end && isTrim(value.charCodeAt(start))) start++;
		while (end > start && isTrim(value.charCodeAt(end - 1))) end--;
		return value.substring(start, end);
	}

	private static function isDigit(code:Int):Bool return code >= 48 && code <= 57;
	private static function isHexDigit(code:Int):Bool {
		return isDigit(code) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
	}

	private static function validFloat(value:String):Bool {
		var i = 0;
		final length = value.length;
		if (i < length && (value.charCodeAt(i) == 43 || value.charCodeAt(i) == 45)) i++;
		var digits = 0;
		while (i < length && isDigit(value.charCodeAt(i))) {
			i++;
			digits++;
		}
		if (i < length && value.charCodeAt(i) == 46) {
			i++;
			while (i < length && isDigit(value.charCodeAt(i))) {
				i++;
				digits++;
			}
		} else if (digits == 0) {
			return false;
		}
		if (digits == 0) return false;
		if (i < length && (value.charCodeAt(i) == 101 || value.charCodeAt(i) == 69)) {
			i++;
			if (i < length && (value.charCodeAt(i) == 43 || value.charCodeAt(i) == 45)) i++;
			var exponentDigits = 0;
			while (i < length && isDigit(value.charCodeAt(i))) {
				i++;
				exponentDigits++;
			}
			if (exponentDigits == 0) return false;
		}
		return i == length;
	}

	private static function validInt(value:String):Bool {
		var i = 0;
		final length = value.length;
		if (i < length && (value.charCodeAt(i) == 43 || value.charCodeAt(i) == 45)) i++;
		var hexadecimal = i + 1 < length && value.charCodeAt(i) == 48
			&& (value.charCodeAt(i + 1) == 120 || value.charCodeAt(i + 1) == 88);
		if (hexadecimal) i += 2;
		var digits = 0;
		while (i < length && (hexadecimal ? isHexDigit(value.charCodeAt(i)) : isDigit(value.charCodeAt(i)))) {
			i++;
			digits++;
		}
		return digits > 0 && i == length;
	}

	public static function parseFloat(value:String):Float {
		final token = trim(value);
		return validFloat(token) ? Std.parseFloat(token) : Math.NaN;
	}

	public static function parseInt(value:String):Null<Int> {
		final token = trim(value);
		if (!validInt(token)) return null;
		final parsed = Std.parseInt(token);
		if (parsed == null || parsed < -2147483648 || parsed > 2147483647) return null;
		return parsed;
	}

	public static function failedFloat(value:String):Bool return Math.isNaN(parseFloat(value));
	public static function failedInt(value:String):Bool return parseInt(value) == null;
#else
	public static function parseFloat(value:String):Float return Std.parseFloat(value);
	public static function parseInt(value:String):Null<Int> return Std.parseInt(value);
	public static function failedFloat(value:String):Bool return Math.isNaN(Std.parseFloat(value));
	public static function failedInt(value:String):Bool return Std.parseInt(value) == null;
#end
}
