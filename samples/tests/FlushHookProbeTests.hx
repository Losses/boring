package tests;

import std.Env;
import std.Fs;
import std.Test;

/**
 * The per-class flush probe of feature spec 27. The class carries one
 * @:test function and the conventional `flushTestTrace` entry. The Kotlin
 * runner calls the entry on the class instance after the class's tests
 * returned, so the entry writes its marker file when the host set
 * BORING_FLUSH_PROBE_DIR. The TS, Rust, Swift, and Dart runners accept the
 * entry, emit nothing for it, and never call it. Without the variable the
 * entry returns immediately, so the ordinary regression loops write
 * nothing.
 */
class FlushHookProbeTests {
    @:test("the class body runs and the flush entry stays outside the test id set")
    public static function classBodyRuns():Void {
        Test.equals(1, 1, "the probe class body runs");
    }

    /**
     * The conventional per-class flush entry. It registers no test id;
     * the Kotlin runner calls it on the instance once every test of this
     * class returned.
     */
    public static function flushTestTrace():Void {
        final directory = Env.get("BORING_FLUSH_PROBE_DIR");
        if (directory == null) {
            return;
        }
        Fs.writeText(directory + "/FlushHookProbeTests.txt", "flushed");
    }
}
