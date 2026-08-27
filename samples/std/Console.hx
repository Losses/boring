package std;

/**
 * Typed extern for the console object available when the JS output runs
 * under bun. It keeps the test runner free of Dynamic and of code injection.
 */
@:native("console")
extern class Console {
	static function log(message:String):Void;
}
