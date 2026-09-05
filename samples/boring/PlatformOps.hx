package boring;

import std.Env;
import std.Fs;
import std.Path;
import std.Process;

/**
 * Host-edge exercises for the platform modules
 * (docs/specs/stdlib/17-platform-modules.md). Each function funnels one
 * std.Fs, std.Env, std.Process.args, or std.Path operation through the
 * lowering of the five targets so a single Haxe test file can assert the
 * same output everywhere.
 */
class PlatformOps {
    /** Whether a path exists. */
    public static function exists(path:String):Bool {
        return Fs.exists(path);
    }

    /** A whole file read back as text. */
    public static function readText(path:String):String {
        return Fs.readText(path);
    }

    /** Write, append, then read the file back. */
    public static function writeAppendRead(path:String, first:String, second:String):String {
        Fs.writeText(path, first);
        Fs.appendText(path, second);
        return Fs.readText(path);
    }

    /** Create a nested directory tree and report it as a directory. */
    public static function makeDirsCheck(path:String):Bool {
        Fs.makeDirs(path);
        return Fs.isDirectory(path);
    }

    /** The names of a directory (order is host-native and unspecified). */
    public static function listDir(path:String):Array<String> {
        return Fs.readDir(path);
    }

    /** The environment entry for a key, or the marker when absent. */
    public static function envGet(key:String):String {
        final value = Env.get(key);
        return value == null ? "<absent>" : value;
    }

    /** Set, read back, remove, and read again. */
    public static function envRoundTrip(key:String, value:String):String {
        Env.set(key, value);
        final afterSet = Env.get(key);
        Env.remove(key);
        final afterRemove = Env.get(key);
        return textOr(afterSet, "<null>") + "|" + textOr(afterRemove, "<absent>");
    }

    /** The entry text when present, the marker when absent. */
    static function textOr(value:Null<String>, marker:String):String {
        return value == null ? marker : value;
    }

    /** The first program argument, or the marker when none was passed. */
    public static function firstArg():String {
        final args = Process.args();
        return args.length > 0 ? args[0] : "<none>";
    }

    public static function join(a:String, b:String):String {
        return Path.join(a, b);
    }

    public static function dirname(p:String):String {
        return Path.dirname(p);
    }

    public static function normalize(p:String):String {
        return Path.normalize(p);
    }

    /** The home directory through a key std.Env can set. */
    public static function home():String {
        final value = Env.get("PLATFORM_TEST_HOME");
        return value == null ? "<absent>" : value;
    }
}
