package std;

/**
 * Filesystem host edges (docs/specs/stdlib/17-platform-modules.md).
 * A platform module: each target's expression compiler lowers every
 * static call inline at the call site, and no runtime module implements
 * the class. A module that never calls std.Fs never mentions a host
 * filesystem API. On a host with no filesystem (a browser) the lowered
 * call raises the haxe.Exception mapping with the fixed unavailability
 * message; compilation always succeeds and host support is decided at
 * the call.
 */
extern class Fs {
    /** Whether a path exists. */
    public static function exists(path:String):Bool;

    /** Read a whole file as text. Raises the haxe.Exception mapping on failure. */
    public static function readText(path:String):String;

    public static function writeText(path:String, data:String):Void;

    public static function appendText(path:String, data:String):Void;

    /** Create a directory and missing parents. */
    public static function makeDirs(path:String):Void;

    /** Entry names of a directory, without the directory part. The list
        never contains "." or ".."; its order is unspecified and each host
        returns its native order. */
    public static function readDir(path:String):Array<String>;

    public static function isDirectory(path:String):Bool;
}
