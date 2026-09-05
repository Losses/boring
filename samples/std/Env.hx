package std;

/**
 * Environment host edges (docs/specs/stdlib/17-platform-modules.md).
 * A platform module: each target's expression compiler lowers every
 * static call inline at the call site, and no runtime module implements
 * the class. The module exposes get/set/remove only; enumeration is out
 * of scope. On a browser host std.Env maps to localStorage, where a
 * missing key reads as null (the direct Null<String> match); on node it
 * maps to process.env.
 */
extern class Env {
    /** The value of an environment entry, null when absent. */
    public static function get(key:String):Null<String>;

    public static function set(key:String, value:String):Void;

    public static function remove(key:String):Void;
}
