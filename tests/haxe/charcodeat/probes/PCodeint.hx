// Source-acceptance probe (the Int-context shape): out-of-range
// charCodeAt(100) assigned to a NON-NULLABLE Int on the six-unit
// literal "abcdef".
//
// Source-domain finding (pinned Haxe 4.3.7): this shape IS
// source-accepted. The plain 4.3.7 typer performs no strict nullability
// enforcement by default (even `var c:Int = null` typechecks), so the
// `Null<Int>` return of charCodeAt is assignable to `Int` with no
// diagnostic. The raw evidence is therefore an EMPTY stderr with exit
// 0; the absence of a diagnostic is the observation that settles the
// source domain. Compiled standalone by run.sh against the plain
// toolchain and re-probed through the full generation pipeline.
class PCodeint {
	public static function main():Void {
		var c:Int = "abcdef".charCodeAt(100);
		std.Console.log("codeInt=" + c);
	}
}
