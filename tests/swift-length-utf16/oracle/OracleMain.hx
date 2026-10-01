package oracle;

/**
 * Haxe oracle entry for the coalescing String.length fixture. Runs on
 * the interpreter target only (see oracle.hxml); it is deliberately
 * outside the Swift codegen scope because haxe.Sys does not type under
 * the Swift std shadow.
 */
class OracleMain {
	static function main() {
		final text = "a😀b";
		// Haxe eval (interp) counts code points: prints 3.
		Sys.println("eval-length " + lenfix.CharCount.charCount(text));
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
