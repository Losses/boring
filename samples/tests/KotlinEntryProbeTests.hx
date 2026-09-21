package tests;

import std.Env;
import std.Fs;

/**
 * The class test entry probe of feature spec 19. The class carries no
 * @:test function and declares the conventional runTestEntries entry. The
 * Kotlin runner reaches the class through that entry and holds no test id
 * for it, so the cross-target test id set is unchanged. The entry writes its
 * marker file when the host set BORING_KOTLIN_ENTRY_PROBE_DIR and returns
 * immediately otherwise, so the ordinary regression loops write nothing.
 */
class KotlinEntryProbeTests {
    /**
     * The conventional class test entry. It registers no test id; the Kotlin
     * runner calls it once on the class, after the @:test classes returned.
     */
    public static function runTestEntries():Void {
        final directory = Env.get("BORING_KOTLIN_ENTRY_PROBE_DIR");
        if (directory == null) {
            return;
        }
        Fs.writeText(directory + "/KotlinEntryProbeTests.txt", "entered");
    }
}
