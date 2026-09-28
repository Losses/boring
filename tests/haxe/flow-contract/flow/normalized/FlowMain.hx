package flow.normalized;

/** Entry that runs every normalized flow case with its authored input and prints one result line. */
class FlowMain {
    public static function main():Void {
        line("guardInsideSkippedBranch.flag.true.null", FlowCases.guardInsideSkippedBranch(true, null));
        line("guardInsideSkippedBranch.flag.false.null", FlowCases.guardInsideSkippedBranch(false, null));
        line("guardInsideSkippedBranch.flag.false.box3", FlowCases.guardInsideSkippedBranch(false, new Cell(3)));
        line("guardInsideSkippedBranch.flag.true.box3", FlowCases.guardInsideSkippedBranch(true, new Cell(3)));
        line("writeAfterExitGuard.box3.null", FlowCases.writeAfterExitGuard(new Cell(3), null));
        line("writeAfterExitGuard.box3.box1", FlowCases.writeAfterExitGuard(new Cell(3), new Cell(1)));
        line("writeAfterExitGuard.null.box1", FlowCases.writeAfterExitGuard(null, new Cell(1)));
        line("writeAfterExitGuard.null.null", FlowCases.writeAfterExitGuard(null, null));
        line("joinedWrite.true.box3.null", FlowCases.joinedWrite(true, new Cell(3), null));
        line("joinedWrite.true.box3.box2", FlowCases.joinedWrite(true, new Cell(3), new Cell(2)));
        line("joinedWrite.false.box3.null", FlowCases.joinedWrite(false, new Cell(3), null));
        line("joinedWrite.false.box3.box2", FlowCases.joinedWrite(false, new Cell(3), new Cell(2)));
        line("joinedWrite.true.null.box2", FlowCases.joinedWrite(true, null, new Cell(2)));
        line("joinedExitingWrite.true.box3.null", FlowCases.joinedExitingWrite(true, new Cell(3), null));
        line("joinedExitingWrite.false.box3.null", FlowCases.joinedExitingWrite(false, new Cell(3), null));
        line("joinedExitingWrite.false.box3.box2", FlowCases.joinedExitingWrite(false, new Cell(3), new Cell(2)));
        line("joinedExitingWrite.true.null.box2", FlowCases.joinedExitingWrite(true, null, new Cell(2)));
        line("normalizationPresentControl.box3", FlowCases.normalizationPresentControl(new Cell(3)));
        line("normalizationPresentControl.null", FlowCases.normalizationPresentControl(null));
        line("normalizedBinding.box3", FlowCases.normalizedBinding(new Cell(3)));
        line("normalizedBinding.null", FlowCases.normalizedBinding(null));
        line("sequentialWriteAfterChain.box4", FlowCases.sequentialWriteAfterChain(new Cell(4)));
        line("sequentialWriteAfterChain.box0", FlowCases.sequentialWriteAfterChain(new Cell(0)));
        line("sequentialWriteAfterChain.null", FlowCases.sequentialWriteAfterChain(null));
        line("hostBits.unitFloatIsOne", Std.string(HostBits.unitFloatIsOne()));
    }

    static function line(name:String, value:String):Void {
        std.Console.log(name + "=" + value);
    }
}
