// expect: coalesced default expression may reference earlier parameters only
class Case {
	static function main() {
		invalid(1, null);
	}

	static function invalid(first:Int, p:Null<Int>, later:Int):Int {
		var normalized = p == null ? first + later : p;
		return normalized;
	}
}
