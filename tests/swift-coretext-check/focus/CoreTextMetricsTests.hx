package focus;

import focus.CTFont;
import focus.CoreTextMetricsSupport;
import focus.Unrelated;
import std.Fs;

/**
    The minimal Core Text consumption point, now a permanent check: build a
    font through each bridge shape, read ascent/descent, and write the
    measured numbers. The macOS CI step compiles the generated tree and runs
    this test, so a mechanism that emits text that cannot compile (or a
    bridge that traps at run time) fails the check instead of a probe.
**/
@:swiftImport("CoreText")
@:testOnly
class CoreTextMetricsTests {
    @:test
    public static function readsMetricsFromEveryConstructionPath():Void {
        // A module that names no platform symbol stays in the same tree and
        // its generated file must carry no import line (the emit test asserts it).
        var report = "unrelated=" + Std.string(Unrelated.twice(2)) + "\n";
        final named:CTFont = CoreTextMetricsSupport.namedFont("Helvetica", 48.0);
        report += "named ascent=" + Std.string(CoreTextMetricsSupport.ascentOf(named))
            + " descent=" + Std.string(CoreTextMetricsSupport.descentOf(named)) + "\n";
        final cstring:Null<CTFont> = CoreTextMetricsSupport.cStringFont("Helvetica", 48.0);
        if (cstring != null) {
            report += "cstring ascent=" + Std.string(CoreTextMetricsSupport.ascentOf(cstring))
                + " descent=" + Std.string(CoreTextMetricsSupport.descentOf(cstring)) + "\n";
        }
        final units:Null<CTFont> = CoreTextMetricsSupport.unitsFont("Helvetica", 48.0);
        if (units != null) {
            report += "units ascent=" + Std.string(CoreTextMetricsSupport.ascentOf(units))
                + " descent=" + Std.string(CoreTextMetricsSupport.descentOf(units)) + "\n";
        }
        final system:Null<CTFont> = CoreTextMetricsSupport.systemFont(48.0);
        if (system != null) {
            report += "system-ui ascent=" + Std.string(CoreTextMetricsSupport.ascentOf(system))
                + " descent=" + Std.string(CoreTextMetricsSupport.descentOf(system)) + "\n";
        }
        Fs.makeDirs("out/swift-coretext-check");
        Fs.writeText("out/swift-coretext-check/metrics.txt", report);
    }
}
