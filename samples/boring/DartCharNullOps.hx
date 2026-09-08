package boring;

class DartCharNullOps {
	public static function argShape(s:String):Int {
		return clamp(s.charCodeAt(0));
	}

	static function clamp(c:Int):Int {
		return c < 0 ? 0 : c;
	}

	public static function boundArgShape(s:String):Int {
		final code = s.charCodeAt(0);
		return clamp(code);
	}

	public static function compareShape(s:String):Bool {
		final high = s.charCodeAt(1);
		final low = s.charCodeAt(0);
		return high < low;
	}

	public static function returnShape(s:String):Int {
		return s.charCodeAt(2);
	}
}
