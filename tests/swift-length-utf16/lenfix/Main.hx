package lenfix;

/**
 * Fixture for the coalescing-default String.length unit bug.
 *
 * `?count:Int` with a call that omits it forces the coalescing-default
 * path (DefaultArgExpander). The `text.length` read inside the ternary
 * must lower to a UTF-16 code-unit count, matching the expression path:
 * "a😀b" has 4 UTF-16 units but 3 grapheme clusters
 * (Swift String.count) and 3 code points (Haxe eval .length).
 */
class Main {
	static function charCount(text:String, ?count:Int):Int {
		return count == null ? text.length : count;
	}

	static function main() {
		final text = "a😀b";
		// Haxe eval (interp) counts code points: prints 3.
		Sys.println("eval-length " + charCount(text));
		// The cross-target Haxe contract (UTF-16 targets: js, jvm, ...)
		// is UTF-16 code units: prints 4. Swift output must match this.
		Sys.println("utf16-units " + utf16Units(text));
	}

	/**
	 * Explicit UTF-16 code-unit count. On eval, charCodeAt returns a full
	 * code point per index, so an astral code point contributes 2 units.
	 */
	static function utf16Units(s:String):Int {
		var n = 0;
		for (i in 0...s.length)
			n += s.charCodeAt(i) > 0xFFFF ? 2 : 1;
		return n;
	}
}
