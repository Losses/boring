package boring;

#if ts_output
/**
 * TS18047 minimal reproduction (r42 A8-A11, cluster C4 "nullable signature, non-null body").
 *
 * Real-world origin: PunctuationGeometryStage.isDigitChar(code:Null<Int>)
 * comparing `code >= 0x30 && code <= 0x39`.
 *
 * ## Haxe type-check verdict (Haxe 4.3.7, probe at .tq-logs/viii/haxe-typecheck-probe/)
 *
 *     public static function isDigit(code:Null<Int>):Bool {
 *         return code >= 48 && code <= 57;
 *     }
 *
 * Haxe ACCEPTS this body without error.  `Null<Int>` is permissively
 * unifiable with the comparison operands — Haxe does NOT prove `code`
 * non-null at the type level; it allows the comparison and, in its own
 * -js backend, wraps the body in a null guard (`if(code >= 48){
 * return code <= 57;}else{return false;}`).
 *
 * ## TS emitter gap (pre-fix)
 *
 * TsType.hx:37 renders `Null<Int>` → `number | null`.  TsExpr.expr()
 * at the `TLocal` path (~1432) emits a bare `code` identifier for
 * every reference.  The generated TS body is:
 *
 *     code >= 48 && code <= 57    // code: number | null
 *
 * tsc 5.9.3 --strict reports TS18047 "'code' is possibly 'null'" at
 * every comparison (`code >= 48` and `code <= 57`, two diagnostics).
 *
 * ## Expected post-fix TS
 *
 * The first nullable reference carries a non-null assertion (`code!`);
 * the second reference is narrowed by TS control-flow analysis.  The
 * cross-target precedent (Kotlin `code!! >= 48 && code <= 57`, Dart
 * `code! >= 48 && code <= 57`) pins this as an erased assertion —
 * `!` is type-only, so the runtime behavior for `isDigit(null)` is
 * `false` (null coerces to 0 for `>=`, and `0 >= 48` is `false`),
 * matching Haxe's own -js output exactly.
 *
 * The assertion in warnstd-ts-regression.test.ts checks for
 * `code! >= 48` and the absence of bare `code >= 48`.
 */
class NullableIntCompare {
	/**
	 * `Null<Int>` parameter used directly in numeric comparison.
	 * Haxe type-checks this; the TS emitter must insert `code!` to
	 * satisfy tsc strict without altering runtime semantics.
	 */
	public static function isDigit(code:Null<Int>):Bool {
		return code >= 48 && code <= 57;
	}
}
#else
class NullableIntCompare {}
#end