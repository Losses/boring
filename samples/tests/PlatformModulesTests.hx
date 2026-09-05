package tests;

import boring.PlatformOps;
import std.Env;
import std.Fs;
import std.Path;
import std.Test;
import tests.PlatformModulesTestSupport;

/**
 * Cross-target semantics of the platform modules and std.Path
 * (docs/specs/stdlib/17-platform-modules.md). The file operations run in
 * out/platform-modules/, which every target's test command can write from
 * the repository root. `std.Env.set` mutates a per-process environment
 * view: on hosts with a mutable process environment (node, Rust, Swift)
 * the native entry changes, and on hosts whose environment is read-only
 * (the JVM and the Dart VM) the compiler emits a process-local overlay
 * seeded from the host environment, so the set/remove round trip is
 * observable everywhere and the five targets agree.
 */
class PlatformModulesTests {
    @:test("std.Fs write append and read round-trip")
    public static function fsRoundTrip():Void {
        PlatformModulesTestSupport.ensureDir();
        final path = PlatformModulesTestSupport.textPath("roundtrip");
        Test.equals("firstsecond", PlatformOps.writeAppendRead(path, "first", "second"));
        Test.equals(true, Fs.exists(path));
        Test.equals(true, Fs.isDirectory(PlatformModulesTestSupport.DIR));
    }

    @:test("std.Fs makeDirs creates a nested directory")
    public static function fsMakeDirs():Void {
        PlatformModulesTestSupport.ensureDir();
        final nested = PlatformModulesTestSupport.DIR + "/a/b/c";
        Test.equals(true, PlatformOps.makeDirsCheck(nested));
        Test.equals(true, Fs.isDirectory(PlatformModulesTestSupport.DIR + "/a/b"));
    }

    @:test("std.Fs readDir omits the dot entries")
    public static function fsReadDir():Void {
        PlatformModulesTestSupport.ensureDir();
        Test.equals(true, PlatformModulesTestSupport.noDotEntries(PlatformModulesTestSupport.DIR));
        Test.equals(true, Fs.exists(PlatformModulesTestSupport.DIR));
    }

    @:test("std.Env set and remove are observable through get")
    public static function envRoundTrip():Void {
        final key = "BORING_PLATFORM_TEST_KEY";
        Test.equals("value|<absent>", PlatformOps.envRoundTrip(key, "value"));
    }

    @:test("std.Env get reports an absent entry as null")
    public static function envAbsent():Void {
        Test.equals("<absent>", PlatformOps.envGet("BORING_PLATFORM_TEST_ABSENT"));
    }

    @:test("std.Path normalizes mixed separators and dot segments")
    public static function pathNormalize():Void {
        Test.equals("a/b/c", PlatformOps.normalize("a\\b/c"));
        Test.equals("a/c", PlatformOps.normalize("a/./b/../c"));
        Test.equals("../b", PlatformOps.normalize("a/../../b"));
        Test.equals("/b", PlatformOps.normalize("/a/../b"));
        Test.equals("C:/b", PlatformOps.normalize("C:\\a\\..\\b"));
        Test.equals("C:/", PlatformOps.normalize("C:\\a\\..\\"));
        Test.equals("a/b", PlatformOps.join("a", "b"));
        Test.equals("/abs", PlatformOps.join("a", "/abs"));
        Test.equals("C:/win", PlatformOps.join("a", "C:/win"));
    }

    @:test("std.Path dirname follows the kind table")
    public static function pathDirname():Void {
        Test.equals(".", PlatformOps.dirname("."));
        Test.equals(".", PlatformOps.dirname(""));
        Test.equals("/", PlatformOps.dirname("/"));
        Test.equals("C:/", PlatformOps.dirname("C:/a"));
        Test.equals("a/b", PlatformOps.dirname("a/b/c"));
        Test.equals(".", PlatformOps.dirname("a"));
        // The spec's own kind-table examples: UNC keeps its root and
        // never strips it, a drive-absolute root keeps its separator,
        // and a root-relative path stops at its root.
        Test.equals("//s/share", PlatformOps.dirname("//s/share/a"));
        Test.equals("//s/share", PlatformOps.dirname("\\\\s\\share\\a"));
        Test.equals("/", PlatformOps.dirname("/a"));
        Test.equals("//s/share", PlatformOps.dirname("//s/share"));
    }

    @:test("std.Path normalize follows the kind table")
    public static function pathNormalizeKinds():Void {
        // Device paths return verbatim: after \\?\ Win32 accepts no
        // separator translation and no dot resolution.
        Test.equals("\\\\?\\C:\\x", PlatformOps.normalize("\\\\?\\C:\\x"));
        Test.equals("\\\\?\\C:\\a\\..\\x", PlatformOps.normalize("\\\\?\\C:\\a\\..\\x"));
        // A UNC root survives; dot segments resolve above it and drop
        // at the root.
        Test.equals("//s/share/b", PlatformOps.normalize("//s/share/a/../b"));
        Test.equals("//s/share", PlatformOps.normalize("//s/share/a/../.."));
        // Drive-relative text stays untouched beyond separator
        // translation (per-drive cwd is host state a string layer
        // does not have).
        Test.equals("C:a/../b", PlatformOps.normalize("C:a\\..\\b"));
        // POSIX double slash keeps its leading pair.
        Test.equals("//a/b", PlatformOps.normalize("//a/b"));
    }

    @:test("std.Path join keeps absolute and device seconds")
    public static function pathJoinKinds():Void {
        Test.equals("\\\\?\\C:\\x", PlatformOps.join("a", "\\\\?\\C:\\x"));
        Test.equals("//s/share", PlatformOps.join("a", "//s/share"));
        Test.equals("C:/win", PlatformOps.join("a", "C:/win"));
        Test.equals("/abs", PlatformOps.join("a", "/abs"));
        Test.equals("a/b", PlatformOps.join("a", "b"));
    }

    @:test("std.Path expandHome reads HOME through std.Env")
    public static function pathExpandHome():Void {
        final original = Env.get("HOME");
        Env.set("HOME", "/home/probe");
        Test.equals("/home/probe", Path.expandHome("~"));
        Test.equals("/home/probe/x", Path.expandHome("~/x"));
        Test.equals("/home/probe", Path.expandHome("~\\"));
        Test.equals("/abs", Path.expandHome("/abs"));
        if (original != null) {
            Env.set("HOME", original);
        } else {
            Env.remove("HOME");
        }
    }
}
