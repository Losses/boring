package boring;

#if ts_output
/**
 * TS2322 minimal reproduction (r42 A2-A5, cluster C1 "atomOrFail not migrated").
 *
 * Real-world origin: PunctuationGeometryLedgerCoverageTest passing a
 * `builder.build(...)` (Null<PunctuationAtom>) result inside `[atom]`
 * to `PunctuationGeometryLedger.from(..., atoms:Array<PunctuationAtom>)`.
 *
 * ## Haxe type-check verdict (Haxe 4.3.7, probe at .tq-logs/viii/haxe-typecheck-probe/)
 *
 *     public static function pass(atom:Null<Atom>):Bool {
 *         return consume([atom]);
 *     }
 *
 * Haxe ACCEPTS this body without error.  `Null<Atom>` (where `Atom` is
 * a plain class) is permissively unifiable with the non-null element
 * type — Haxe does NOT narrow `atom` at this call site.  Haxe's own
 * -js backend emits `[atom]` without any guard (the bare `[atom]` in
 * probe-out.js).
 *
 * ## TS emitter gap (pre-fix)
 *
 * TsType.hx:37 renders `Null<Atom>` → `Atom | null`.  The array-literal
 * element passes through `requiredArgText`/`callArgTexts` without
 * nullability detection, so the generated TS passes `[atom]` where
 * `atom: Atom | null`, producing the array type `(Atom | null)[]`.
 * Passed to `consume(atoms: Atom[])`, tsc reports:
 *
 *   error TS2322: Type '(Atom | null)[]' is not assignable to type 'Atom[]'.
 *
 * ## Expected post-fix TS
 *
 * The array-literal element carries a non-null assertion (`[atom!]`)
 * so that the array is `Atom[]`, not `(Atom | null)[]`.  `!` is erased
 * at runtime: `pass(null)` executes as `consume([null])` → `[null].
 * length > 0` → `true`, matching Haxe's own -js output exactly.  The
 * assertion is type-only and does not change runtime behavior.
 *
 * The assertion in warnstd-ts-regression.test.ts checks for `[atom!]`
 * and the absence of bare `[atom]`.
 */
class NullableArrayElemArg {
	/**
	 * Nullable element in array literal passed to non-null `Array<Atom>`.
	 * Haxe type-checks this; the TS emitter must insert `[atom!]` to
	 * satisfy tsc strict without altering runtime semantics.
	 */
	public static function pass(atom:Null<Atom>):Bool {
		return NullableArrayElemArg.consume([atom]);
	}

	public static function consume(atoms:Array<Atom>):Bool {
		return atoms.length > 0;
	}
}
#else
class NullableArrayElemArg {}
#end

#if ts_output
class Atom {
	public function new() {}
}
#else
class Atom {}
#end