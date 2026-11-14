package kotlinpack;

/**
    The capturing-closure smart-cast shape: a null-initialized local is written
    inside the nested block the emitter wraps in a run block for a
    for-in-call loop, so Kotlin refuses to smart-cast it at the later null
    guard and the read needs its own extraction.
**/
class CaptureFixture {
    static function ends():Array<Int> {
        return [1, 2, 3];
    }

    /** The best edge over the candidate ends, or -1 when none was kept. */
    public static function solve():Int {
        var terminalBest:Null<Edge> = null;
        var start = 0;
        while (start < 3) {
            for (e in ends()) {
                for (p in ends()) {
                    if (p > 1) {
                        if (terminalBest == null || e > terminalBest.end)
                            terminalBest = new Edge(e);
                    }
                }
            }
            start++;
        }
        return terminalBest == null ? -1 : terminalBest.end;
    }
}

/** One candidate edge. */
class Edge {
    public final end:Int;

    public function new(end:Int) {
        this.end = end;
    }
}
