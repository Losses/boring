/**
 * Shared test-support functions for the value record tests, as ruled in
 * docs/specs/features/27-class-members-and-records.md: a test class carries
 * `@:test` functions and nothing else, so probes live in an ordinary
 * class and cross into the tests through the normal member lowering.
 */

package tests;

import boring.ValueException;
import boring.ValueRecord;

class ValueRecordProbes {
    public static function ctorRejected(start:Int, end:Int):Bool {
        var rejected = false;
        try {
            new ValueRecord(start, end, "probe");
        } catch (_:ValueException) {
            rejected = true;
        }
        return rejected;
    }
}
