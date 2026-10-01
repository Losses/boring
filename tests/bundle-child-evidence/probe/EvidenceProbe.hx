package;

import haxe.Json;
import js.Syntax;
import driver.ChildEvidence as ChildEvidence;
import driver.ChildEvidence.ChildContext;
import driver.ChildEvidence.ChildEvidenceError;
import driver.ChildEvidence.ChildEvidenceRecord;
import driver.ChildEvidence.ChildEnvironment;
import driver.ChildEvidence.ChildExecution;
import driver.ChildEvidence.ChildOutcome;
import driver.ChildEvidence.ChildRun;
import driver.ChildEvidence.EnvironmentOverride;
import driver.ChildEvidence.NodeFile;

/**
    Focused probe for the child evidence module of feature spec 59. It reads
    one plan file and runs the module the way `Driver.step` does, or drives
    the allocator API directly when the plan asks for that. It prints the
    execution result with the record it wrote. It holds no failure switch and
    no copy of the module's decisions; it is only a caller.

    Plan modes:
    - `step` (default): `ChildEvidence.begin` plus `execute`, the driver path.
    - `capture`: an explicit `ChildRun.open` with the plan's byte limit, then
      `capture`, which is the allocator API a caller with its own limit uses.
    - `allocate`: two `ChildRun.allocate` calls from one process with the same
      stamp and process identity, which is the deterministic same-name
      collision the exclusive allocator has to resolve.

    Run through tests/bundle-child-evidence/probe/probe.hxml.
**/
class EvidenceProbe {
    public static function main():Void {
        final argv:Array<String> = Syntax.code("process.argv.slice(2)");
        final plan:ProbePlan = Json.parse(readText(argv[0]));
        if (plan.mode == "allocate") {
            write(allocationReport(plan));
            return;
        }
        if (plan.mode == "convert") {
            write(conversionReport(plan));
            return;
        }
        try {
            final execution = plan.mode == "capture" ? captureWithLimit(plan) : captureThroughDriverPath(plan);
            write(executionReport(execution, null));
        } catch (problem:ChildEvidenceError) {
            // An evidence failure is itself an observation: the caller sees the
            // failure status and the record the module managed to write.
            write(executionReport(null, problem));
            Syntax.code("process.exit(1)");
        }
    }

    static function captureThroughDriverPath(plan:ProbePlan):ChildExecution {
        ChildEvidence.begin(plan.projectPath);
        return ChildEvidence.execute(context(plan), plan.cmd, plan.args, plan.cwd, environment(plan));
    }

    static function captureWithLimit(plan:ProbePlan):ChildExecution {
        final run = ChildRun.open(plan.evidenceParent, plan.projectPath, plan.maxBufferBytes);
        return run.capture(context(plan), plan.cmd, plan.args, plan.cwd, environment(plan));
    }

    /**
        Runs the production host conversion over one real host throw. The value
        is thrown through the host and caught through Haxe's wildcard catch, so
        the conversion sees exactly what a captured spawn would hand it.
    **/
    static function conversionReport(plan:ProbePlan):String {
        final caught = caughtHostValue(plan.native);
        final report = ChildEvidence.hostErrorOf(caught);
        return Json.stringify({
            kind: plan.native,
            caughtMessage: caught.message,
            code: report.code,
            message: report.message,
        });
    }

    /** Throws one native host value of the requested kind and catches it. */
    static function caughtHostValue(kind:Null<String>):haxe.Exception {
        try {
            switch (kind) {
                case "system-code":
                    Syntax.code("throw Object.assign(new Error('the host refused the request'), {code: 'EACCES'})");
                case "plain-error":
                    Syntax.code("throw new Error('the host failed without a code')");
                case "string":
                    Syntax.code("throw 'a plain text failure from the host'");
                case "number":
                    Syntax.code("throw 4101");
                case _:
                    Syntax.code("throw {code: 4101, message: 'a numeric code from the host'}");
            }
        } catch (problem:haxe.Exception) {
            return problem;
        }
        throw new haxe.Exception("the host value was not caught");
    }

    /**
        Two allocations that request the same name in one process. The first
        one takes it; the second has to resolve the exclusive collision and
        end up with a different directory and a different identity.
    **/
    static function allocationReport(plan:ProbePlan):String {
        final stampMs = plan.stampMs;
        final processId = plan.processId;
        final first = ChildRun.allocate(plan.evidenceParent, plan.projectPath, plan.maxBufferBytes, stampMs, processId);
        final markerPath = first.directory + "/marker.txt";
        NodeFile.writeFileSync(markerPath, "first allocation\n");
        final before = readText(markerPath);
        final second = ChildRun.allocate(plan.evidenceParent, plan.projectPath, plan.maxBufferBytes, stampMs, processId);
        return Json.stringify({
            firstDirectory: first.directory,
            firstInvocationId: first.invocationId,
            secondDirectory: second.directory,
            secondInvocationId: second.invocationId,
            firstMarkerBeforeSecond: before,
            firstMarkerAfterSecond: readText(markerPath),
        });
    }

    static function context(plan:ProbePlan):ChildContext {
        return {bundle: plan.bundle, action: plan.action, step: plan.step};
    }

    static function environment(plan:ProbePlan):ChildEnvironment {
        var environment = ChildEnvironment.inherited();
        if (plan.overrides != null) {
            for (entry in plan.overrides) {
                environment = environment.withOverride(entry.name, entry.value);
            }
        }
        return environment;
    }

    static function executionReport(execution:Null<ChildExecution>, failure:Null<ChildEvidenceError>):String {
        // The record is the authority for the recorded facts, so a caller that
        // only received a failure still sees the outcome the record states.
        final recordPath = execution == null ? failure.recordPath : execution.recordPath;
        final record:Null<ChildEvidenceRecord> = recordPath == null
            || !NodeFile.existsSync(recordPath) ? null : Json.parse(readText(recordPath));
        return Json.stringify({
            evidenceError: failure == null ? null : failure.message,
            evidenceDetail: failure == null ? null : failure.detail,
            outcome: record == null ? (execution == null ? null : outcomeName(execution.outcome)) : record.outcome,
            exitStatus: record == null ? (execution == null ? null : execution.exitStatus) : record.exitStatus,
            signal: record == null ? (execution == null ? null : execution.signal) : record.signal,
            launchError: record == null ? (execution == null ? null : execution.launchError) : record.launchError,
            captureComplete: record == null ? (execution == null ? false : execution.captureComplete) : record.captureComplete,
            captureError: record == null ? (execution == null ? (failure == null ? null : failure.detail) : execution.captureError) : record.captureError,
            stdoutAvailable: record == null ? (execution == null ? false : execution.stdoutAvailable) : record.stdoutAvailable,
            stderrAvailable: record == null ? (execution == null ? false : execution.stderrAvailable) : record.stderrAvailable,
            succeeded: execution != null && execution.succeeded(),
            reportedCode: execution == null ? -1 : execution.reportedCode(),
            stdoutText: execution == null ? "" : execution.stdoutText(),
            stderrText: execution == null ? "" : execution.stderrText(),
            childDirectory: execution == null ? failure.childDirectory : execution.childDirectory,
            sequence: record == null ? (execution == null ? null : execution.sequence) : record.sequence,
            evidenceDirectory: ChildEvidence.directory(),
            record: record,
        });
    }

    static function outcomeName(outcome:ChildOutcome):String {
        return switch (outcome) {
            case OutcomeNormalExit(_): "normal-exit";
            case OutcomeSignaled(_): "signaled";
            case OutcomeLaunchFailed(_): "launch-failed";
            case OutcomeInterrupted(_): "interrupted";
        };
    }

    static function readText(path:String):String {
        return Syntax.code("require('fs').readFileSync({0}, 'utf8')", path);
    }

    static function write(text:String):Void {
        Syntax.code("process.stdout.write({0} + '\\n')", text);
    }
}

typedef ProbePlan = {
    var mode:Null<String>;
    var native:Null<String>;
    var projectPath:String;
    var evidenceParent:Null<String>;
    var maxBufferBytes:Null<Int>;
    var stampMs:Null<Float>;
    var processId:Null<String>;
    var bundle:String;
    var action:String;
    var step:String;
    var cmd:String;
    var args:Array<String>;
    var cwd:String;
    var overrides:Array<EnvironmentOverride>;
};
