package flow;

/** Entry that runs every flow case with its authored input and prints one result line. */
class FlowMain {
    public static function main():Void {
        line("guardInsideSkippedBranch.flag.true.null", FlowCases.guardInsideSkippedBranch(true, null));
        line("guardInsideSkippedBranch.flag.false.box3", FlowCases.guardInsideSkippedBranch(false, new Box(3)));
        line("guardInsideSkippedBranch.flag.true.box3", FlowCases.guardInsideSkippedBranch(true, new Box(3)));
        line("repairGuardDominates.null", FlowCases.repairGuardDominates(null));
        line("repairGuardDominates.box3", FlowCases.repairGuardDominates(new Box(3)));
        line("exitGuardDominates.null", FlowCases.exitGuardDominates(null));
        line("exitGuardDominates.box3", FlowCases.exitGuardDominates(new Box(3)));
        line("writeAfterExitGuard.box3.box1", FlowCases.writeAfterExitGuard(new Box(3), new Box(1)));
        line("writeAfterExitGuard.null.box1", FlowCases.writeAfterExitGuard(null, new Box(1)));
        line("guardThenRead.null", FlowCases.guardThenRead(null));
        line("guardThenRead.box3", FlowCases.guardThenRead(new Box(3)));
        line("joinedWrite.false.box3.null", FlowCases.joinedWrite(false, new Box(3), null));
        line("joinedWrite.true.box3.box2", FlowCases.joinedWrite(true, new Box(3), new Box(2)));
        line("joinedExitingWrite.false.box3.null", FlowCases.joinedExitingWrite(false, new Box(3), null));
        line("joinedExitingWrite.true.box3.box2", FlowCases.joinedExitingWrite(true, new Box(3), new Box(2)));
        line("shortCircuitWrite.box4", FlowCases.shortCircuitWrite(new Box(4)));
        line("shortCircuitRead.box4", FlowCases.shortCircuitRead(new Box(4)));
        line("shortCircuitRead.null", FlowCases.shortCircuitRead(null));
        line("stringLengthAfterGuard.abc", FlowCases.stringLengthAfterGuard("abc"));
        line("stringLengthAfterGuard.null", FlowCases.stringLengthAfterGuard(null));
        line("stringLengthPlain.abc", FlowCases.stringLengthPlain("abc"));
    }

    static function line(name:String, value:String):Void {
        std.Console.log(name + "=" + value);
    }
}
