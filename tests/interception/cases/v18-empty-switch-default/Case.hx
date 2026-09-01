// expect: V18 NonAsciiStringIndex
class Case {
	// The parser hands an empty `default:` arm to the build macro as a
	// placeholder expression whose expr and pos are both null. Reaching the
	// violation below confirms the walker skipped that placeholder and
	// avoided dereferencing a null ExprDef.
	static function afterEmptyDefault(text:String):Int {
		var result = 0;
		switch (text.charCodeAt(0)) {
			case 0x201C:
				result = 1;
			case 0x2018:
				result = 2;
			default:
		}
		return "中文".charCodeAt(0) + result;
	}

	static function main():Void {
		afterEmptyDefault("“");
	}
}
