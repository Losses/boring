package probe;

import std.Fs;

/**
 * The workload of the runner-timeout probe (docs/specs/features/19-testing.md).
 * One call appends a fixed number of short lines to one file. Each append
 * opens, writes, and closes the file, so the wall-clock time follows the
 * cost of those file system calls. That cost is close on both probe
 * hosts, so one count overruns the same budget on each. The count is
 * sized on the slower host with room for a faster machine.
 */
class TimeoutProbeOps {
    public static final ITERATIONS:Int = 1600000;
    public static final DIR:String = "out/timeout-probe";
    public static final PATH:String = "out/timeout-probe/burn.txt";
    static final LINE:String = "boring timeout probe\n";

    /** Runs the workload and returns the number of completed appends. */
    public static function burn():Int {
        Fs.makeDirs(DIR);
        Fs.writeText(PATH, "");
        var appends = 0;
        for (i in 0...ITERATIONS) {
            Fs.appendText(PATH, LINE);
            appends = appends + 1;
        }
        return appends;
    }
}
