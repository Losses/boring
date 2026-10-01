package lenfix;

/**
 * Fixture for the coalescing-default String.length unit bug.
 *
 * `?count:Int` with a call that omits it forces the coalescing-default
 * path (DefaultArgExpander). The `text.length` read inside the ternary
 * must lower to a UTF-16 code-unit count on the Swift target, matching
 * the expression path: "a😀b" has 4 UTF-16 units but 3 grapheme
 * clusters (Swift String.count).
 *
 * The Swift driver is LengthRuntimeTests.swift in this directory; the
 * Haxe oracle entry is oracle/OracleMain.hx (kept out of the codegen
 * scope because haxe.Sys does not type under the Swift std shadow).
 */
class CharCount {
	public static function charCount(text:String, ?count:Int):Int {
		return count == null ? text.length : count;
	}

	static function main() {}
}
