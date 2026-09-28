package flow;

/**
    Bounded flow cases for one question: can a generated use tell a source
    comparison that establishes presence on its reachable incoming paths apart
    from an earlier comparison that establishes nothing?

    Every case copies its parameter into a declared local, pairs one source
    comparison over that local with a later member read of the same local, and
    leaves the decision about the read to the emitter. The control beside each
    case keeps the construct and places the read where the comparison does
    establish presence, so an emitted difference between case and control
    comes from the flow decision and not from the construct.

    The authored inputs keep every listed result defined under the Haxe
    reference run. No case reads a null value through a correct decision; a
    removed presence condition shows in the emitted operation and in the
    downstream compile or run status.
**/
class FlowCases {
    /** Case 1: the repair guard sits inside a branch the caller may skip. */
    public static function guardInsideSkippedBranch(flag:Bool, raw:Null<Box>):String {
        var b:Null<Box> = raw;
        if (flag) {
            if (b == null) {
                b = new Box(6);
            }
        }
        return "w:" + b.width;
    }

    /** Control 1: the same repair guard with no enclosing branch. */
    public static function repairGuardDominates(raw:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b == null) {
            b = new Box(6);
        }
        return "w:" + b.width;
    }

    /** Control 1b: an early-exit guard dominates the read. */
    public static function exitGuardDominates(raw:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b == null) {
            return "absent";
        }
        return "w:" + b.width;
    }

    /** Case 2: an early-exit guard establishes presence, then a write from a nullable input replaces the value. */
    public static function writeAfterExitGuard(raw:Null<Box>, input:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b == null) {
            return "absent";
        }
        b = input;
        return "w:" + b.width;
    }

    /** Control 2: the same guard without the write. */
    public static function guardThenRead(raw:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b == null) {
            return "absent";
        }
        return "w:" + b.width;
    }

    /** Case 3: one reachable arm writes a nullable value and the other arm preserves the guarded binding. */
    public static function joinedWrite(flag:Bool, raw:Null<Box>, input:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b == null) {
            return "absent";
        }
        if (flag) {
            b = input;
        }
        return "w:" + b.width;
    }

    /** Control 3: the writing arm exits, so only the preserving arm reaches the join. */
    public static function joinedExitingWrite(flag:Bool, raw:Null<Box>, input:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b == null) {
            return "absent";
        }
        if (flag) {
            b = input;
            return "w:" + b.width;
        }
        return "w:" + b.width;
    }

    /** Case 4: a short-circuit operand rewrites the dependency before the read after the condition. */
    public static function shortCircuitWrite(raw:Null<Box>):String {
        var b:Null<Box> = raw;
        if (b != null && (b = new Box(9)).width == 9 && b.width == 5) {
            return "nine";
        }
        return "w:" + b.width;
    }

    /** Control 4: the chain reads the value in the operand the left comparison guards. */
    public static function shortCircuitRead(raw:Null<Box>):String {
        var b:Null<Box> = raw;
        return (b != null && b.width > 0) ? "wide:" + b.width : "short";
    }

    /** Baseline: a String member read behind a dominating guard, for the member spelling of a wrapped receiver. */
    public static function stringLengthAfterGuard(raw:Null<String>):String {
        var s:Null<String> = raw;
        if (s == null) {
            return "absent";
        }
        return "len:" + s.length;
    }

    /** Baseline control: the same member read on an unwrapped receiver. */
    public static function stringLengthPlain(s:String):String {
        return "len:" + s.length;
    }
}
