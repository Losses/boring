package std;

/**
 * Typed extern for the process object available when the JS output runs
 * under bun. It keeps the test runner free of Dynamic and of code injection.
 */
@:native("process")
extern class Process {
    static function exit(code:Int):Void;
}
