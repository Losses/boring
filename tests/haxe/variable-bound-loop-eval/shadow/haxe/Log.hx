package haxe;

/**
 * Fixture-local shadow of haxe.Log for the five cross targets. The store's
 * haxe.Log does not typecheck against the compiler's per-target std-shadow:
 * expanding the trace() call types PosInfos in haxe.macro.Expr, which drags
 * the haxe.macro.Context class into the typed set; that class references the
 * eval-target Sys/FileSystem chain, which typechecks the store's
 * haxe.io.Input and haxe.io.Output against the shadowed haxe.io.Bytes and
 * fails on every target with "haxe.io.Bytes has no field getData" (verified
 * 5/5: see REPORT.md). This shadow is a no-op: trace participates in none of
 * the counted expressions, and the per-target native driver prints the
 * observation line instead.
 */
class Log {
	// The cross targets' translatable subset has no Dynamic lowering and
	// requires named typedefs for structure types, so the parameters are
	// typed to the one call this fixture makes: a String payload and the
	// exact four-field structure the typer injects as position info. Naming
	// haxe.macro.Expr.PosInfos instead would type the haxe.macro.Context
	// class and re-trigger the store haxe.io.Input conflict this shadow
	// exists to avoid.
	public static function trace(v:String, ?infos:Pos):Void {}
}

typedef Pos = {
	methodName:String,
	lineNumber:Int,
	fileName:String,
	className:String
}
