package flow.normalized;

/**
    Normalized flow cases for one question: can a generated use tell a source
    comparison that establishes presence on its reachable incoming paths apart
    from an earlier comparison that establishes nothing?

    Every case copies its parameter into a declared local, exposes one path on
    which the source comparison never runs, and closes with a final null test
    whose fallback value is defined for that path. The authored result is
    therefore defined for every absence path, so a case never dereferences null
    and a target that removes the fallback condition shows the difference in its
    own result. The control beside each case keeps the construct and places the
    read where the comparison does establish presence, so an emitted difference
    between case and control comes from the flow decision and not from the
    construct.

    The short-circuit form of the fourth distinction stays with the observation
    group, which holds its source admission result. This group carries the
    sequential form of the same distinction: a write between the guarded chain
    and the normalized read, so the chain's fact does not describe the value at
    the read.
**/
class FlowCases {
    /** Case 1: the repair guard sits inside a branch the caller may skip. */
    public static function guardInsideSkippedBranch(flag:Bool, raw:Null<Cell>):String {
        var b:Null<Cell> = raw;
        if (flag) {
            if (b == null) {
                b = new Cell(6);
            }
        }
        return b == null ? "absent" : "w:" + b.width;
    }

    /** Case 2: an early-exit guard establishes presence, then a write from a nullable input replaces the value. */
    public static function writeAfterExitGuard(raw:Null<Cell>, input:Null<Cell>):String {
        var b:Null<Cell> = raw;
        if (b == null) {
            return "absent";
        }
        b = input;
        return b == null ? "cleared" : "w:" + b.width;
    }

    /** Case 3: one reachable arm writes a nullable value and the other arm preserves the guarded binding. */
    public static function joinedWrite(flag:Bool, raw:Null<Cell>, input:Null<Cell>):String {
        var b:Null<Cell> = raw;
        if (b == null) {
            return "absent";
        }
        if (flag) {
            b = input;
        }
        return b == null ? "cleared" : "w:" + b.width;
    }

    /** Control 3: the writing arm exits with a constant, so only the preserving arm reaches the normalization. */
    public static function joinedExitingWrite(flag:Bool, raw:Null<Cell>, input:Null<Cell>):String {
        var b:Null<Cell> = raw;
        if (b == null) {
            return "absent";
        }
        if (flag) {
            b = input;
            return "exiting";
        }
        return b == null ? "cleared" : "w:" + b.width;
    }

    /** Present-value control: the normalization follows a guard that already establishes presence. */
    public static function normalizationPresentControl(raw:Null<Cell>):String {
        var b:Null<Cell> = raw;
        if (b == null) {
            return "absent";
        }
        return b == null ? "cleared" : "w:" + b.width;
    }

    /** Normalized binding: the fallback result feeds a local whose classification the emitter must state. */
    public static function normalizedBinding(raw:Null<Cell>):String {
        var b:Null<Cell> = raw;
        final w = b == null ? -1 : b.width;
        return "w:" + w;
    }

    /** Case 4 in the admitted sequential form: a write between the guarded chain and the normalized read. */
    public static function sequentialWriteAfterChain(raw:Null<Cell>):String {
        var b:Null<Cell> = raw;
        final held = b != null && b.width > 0;
        if (held) {
            b = null;
        }
        return b == null ? "cleared" : "w:" + b.width;
    }
}
