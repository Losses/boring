package fsprobe;

import std.Console;
import std.Fs;

/**
	Minimal cross-target fixture for the missing-path reading of
	`std.Fs.isDirectory` (docs/specs/stdlib/17-platform-modules.md,
	ruling 2026-10-05: a missing path is not a directory, so the
	predicate returns false and never raises).

	One Haxe source, four target chains: an existing directory must read
	`true` and a path that does not exist must read `false`. The probe
	asserts nothing itself; the runner compares the printed lines, so a
	target that raises instead of returning takes that arm's exit status.

	The Dart target gives `std.Console` no lowering, so this module
	declares a module-local native `print` for it; that branch is a
	fixture edge, not a production ruling.
**/
class IsDirectoryProbe {
	public static final EXISTING = "out/fs-missing-isdirectory/probe/existing-directory";
	public static final MISSING = "out/fs-missing-isdirectory/probe/definitely-missing-directory";

	public static function say(label:String, text:String):Void {
		#if dart_output
		ProbePrint.print(label + "|" + text);
		#else
		Console.log(label + "|" + text);
		#end
	}

	public static function run():Void {
		say("p0", "probe-start");
		say("p1", "existing-isDirectory|" + Std.string(Fs.isDirectory(EXISTING)));
		say("p2", "missing-isDirectory|" + Std.string(Fs.isDirectory(MISSING)));
	}
}

#if dart_output
/**
	Line writer for the Dart target, declared at module level: the Dart
	target lowers a native extern from the same module to a bare call.
**/
@:native("print")
extern class ProbePrint {
	static function print(text:String):Void;
}
#end
