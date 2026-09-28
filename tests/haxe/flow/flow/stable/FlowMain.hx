package flow.stable;

/** Entry that runs the isolation cases with their authored input and prints one result line. */
class FlowMain {
    public static function main():Void {
        line("skippedComparisonGuard.flag.true.null", FlowCases.skippedComparisonGuard(true, null));
        line("skippedComparisonGuard.flag.true.box3", FlowCases.skippedComparisonGuard(true, new Cell(3)));
        line("skippedComparisonGuard.flag.false.box3", FlowCases.skippedComparisonGuard(false, new Cell(3)));
        line("dominatingComparisonGuard.null", FlowCases.dominatingComparisonGuard(null));
        line("dominatingComparisonGuard.box3", FlowCases.dominatingComparisonGuard(new Cell(3)));
        line("hostBits.unitFloatIsOne", Std.string(HostBits.unitFloatIsOne()));
    }

    static function line(name:String, value:String):Void {
        std.Console.log(name + "=" + value);
    }
}
