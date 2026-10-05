package std;

/**
 * Filesystem host edges (docs/specs/stdlib/17-platform-modules.md).
 * A platform module: each target's expression compiler lowers every
 * static call inline at the call site, and no runtime module implements
 * the class. A module that never calls std.Fs never mentions a host
 * filesystem API. A failing read/write call raises std.FsException
 * (FsException.hx) carrying an std.FsError (FsError.hx) with the
 * operation, the path and the normalized kind, so a catch names the one
 * concrete class and reads the kind off `error.error`. On a host with no
 * filesystem (a browser) the lowered call raises
 * std.FsException(Unavailable(..)) with the fixed unavailability message;
 * compilation always succeeds and host support is decided at the call.
 */
extern class Fs {
    /** Whether a path exists. */
    public static function exists(path:String):Bool;

    /** Read a whole file as text. Raises std.FsException on failure. */
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

    /** Delete a regular file. Raises std.FsException on failure. */
    public static function deleteFile(path:String):Void;

    /** Rename a path, replacing an existing regular file destination. Raises std.FsException on failure. */
    public static function rename(from:String, to:String):Void;
}
