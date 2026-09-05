package std;

/**
 * Typed extern for the process object available when the JS output runs
 * under bun. It keeps the test runner free of Dynamic and of code
 * injection. The argument face is a platform module member
 * (docs/specs/stdlib/17-platform-modules.md): each target's expression
 * compiler lowers `args()` inline at the call site, and `exit` binds to
 * the native process exit.
 */
@:native("process")
extern class Process {
    static function exit(code:Int):Void;

    /** The program arguments after the program name. */
    static function args():Array<String>;
}
