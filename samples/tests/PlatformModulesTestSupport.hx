package tests;

import std.Fs;

/**
 * Shared paths of the platform-module tests
 * (docs/specs/stdlib/17-platform-modules.md): test classes carry only
 * @:test methods, so the working directory and helpers live here. The
 * std.Fs face has no delete, so the tests are idempotent: every run
 * writes the same fixed paths and asserts on their contents, never on
 * the total contents of a directory that earlier runs may have filled.
 */
class PlatformModulesTestSupport {
    public static final DIR = "out/platform-modules";

    public static function textPath(name:String):String {
        return DIR + "/" + name + ".txt";
    }

    public static function ensureDir():Void {
        Fs.makeDirs(DIR);
    }

    /** True when a name occurs in the directory listing. */
    public static function hasEntry(dir:String, name:String):Bool {
        final names = Fs.readDir(dir);
        for (i in 0...names.length) {
            if (names[i] == name) {
                return true;
            }
        }
        return false;
    }

    /** True when the listing is free of the dot entries. */
    public static function noDotEntries(dir:String):Bool {
        final names = Fs.readDir(dir);
        for (i in 0...names.length) {
            if (names[i] == "." || names[i] == "..") {
                return false;
            }
        }
        return true;
    }
}
