package probe;

import probe.TimeoutProbeOps;
import std.Test;

/**
 * The runner-timeout probe of feature spec 19: one test whose body passes
 * the wall-clock budget of std.Test.run. The probe entries beside this
 * file compile it on their own, and it is registered in none of the eight
 * generation entries under examples/. The probe is slow and red by
 * construction, so entering an example entry would make that entry slow
 * and red for every ordinary run.
 */
class TimeoutProbeTests {
    @:test("a body that overruns the test budget is recorded as a failure")
    public static function overrun():Void {
        final appends = TimeoutProbeOps.burn();
        // Every append completes, so this assertion holds and the recorded
        // verdict can only come from the budget check of Test.run.
        Test.ok(appends == TimeoutProbeOps.ITERATIONS, "the workload loop completes");
    }
}
