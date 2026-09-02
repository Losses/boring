// expect: coalesced default expression is not sanctioned
class Case {
	static function main() {
		invalid(null);
	}

	static function invalid(p:Null<Dynamic>):Dynamic {
		var normalized = p == null ? {bad: 1} : p;
		return normalized;
	}
}
