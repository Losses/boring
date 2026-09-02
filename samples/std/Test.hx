package std;

/**
 * Standard test assertion API (docs/specs/features/19-testing.md).
 * In Haxe reference JavaScript output, calls bind to __boring_test installed
 * by the runner. Transpile targets route std.Test to their runtime package.
 */
@:native("__test_shim")
extern class Test {
	static function run(id:String, name:String, body:() -> Void):Void;
	static function ok(condition:Bool, message:String = null):Void;
	static function equals<T>(expected:ReadOnlyArray<T>, actual:ReadOnlyArray<T>, message:String = null):Void;
	static function equals<T>(expected:T, actual:T, message:String = null):Void;
	static function fail(message:String):Void;
}
