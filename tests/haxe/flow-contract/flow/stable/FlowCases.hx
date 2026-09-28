package flow.stable;

/**
    Isolation group for one decision: does the emitter's comparison-position
    record reach a generated use of a local that no arm ever reassigns?

    The two cases keep the same construct and differ only in where the
    comparison sits. The read stays unguarded, because an arm would supply the
    fact and hide the decision. The authored inputs keep every listed result
    defined; the input on which the skipped comparison leaves a null value is
    not authored, so no case dereferences null at run time. The observation is
    the emitted separator and the downstream compile status.
**/
class FlowCases {
    /** Case: the only comparison sits inside a branch the caller may skip. */
    public static function skippedComparisonGuard(flag:Bool, raw:Null<Cell>):String {
        final b:Null<Cell> = raw;
        if (flag) {
            if (b == null) {
                return "absent";
            }
        }
        return "w:" + b.width;
    }

    /** Control: the same comparison dominates the read. */
    public static function dominatingComparisonGuard(raw:Null<Cell>):String {
        final b:Null<Cell> = raw;
        if (b == null) {
            return "absent";
        }
        return "w:" + b.width;
    }
}
