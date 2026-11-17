package probe;

import probe.CTFont;
import probe.CoreTextMetricsSupport;
import std.Fs;

/**
    The minimal Core Text consumption point: build two fonts and read their
    ascent and descent. The probe exists for the emitted call text and the
    measured numbers, so the body stays one line per API and the whole report
    goes to a file the job prints.
**/
@:testOnly
class CoreTextMetricsTests {
    @:test
    public static function createFontAndReadMetrics():Void {
        final named:CTFont = CoreTextMetricsSupport.createNamedFont("Helvetica", 48.0);
        final namedAscent:Float = CoreTextMetricsSupport.ascentOf(named);
        final namedDescent:Float = CoreTextMetricsSupport.descentOf(named);
        var report = "helvetica ascent=" + Std.string(namedAscent) + " descent=" + Std.string(namedDescent) + "\n";
        final system:Null<CTFont> = CoreTextMetricsSupport.createSystemFont(48.0);
        if (system != null) {
            final systemAscent:Float = CoreTextMetricsSupport.ascentOf(system);
            final systemDescent:Float = CoreTextMetricsSupport.descentOf(system);
            report += "system-ui ascent=" + Std.string(systemAscent) + " descent=" + Std.string(systemDescent) + "\n";
        }
        Fs.makeDirs("out/coretext-probe");
        Fs.writeText("out/coretext-probe/metrics.txt", report);
    }
}
