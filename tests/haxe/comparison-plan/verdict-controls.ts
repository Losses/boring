import { decideStage, finishProcedure, type StageObservation } from "./stage-verdict.ts";

const expectedOutput = "authored body\n";
const expectedZero = {kind: "zero"} as const;
type LeafEvaluation = {ok: boolean; reasons: string[]; exitStatus: 0 | 1};
type ControlEvidence = {
	name: string;
	stageAccepted: boolean;
	procedureExitStatus: 0 | 1;
	failures: string[];
	downstreamAttempted: boolean;
};

function observation(overrides: Partial<StageObservation> = {}): StageObservation {
	return {
		outcome: "normal-exit",
		exitStatus: 0,
		signal: null,
		captureComplete: true,
		evidenceError: null,
		stdoutAvailable: true,
		stderrAvailable: true,
		recordAvailable: true,
		stdoutArchiveAvailable: true,
		stderrArchiveAvailable: true,
		stdoutText: expectedOutput,
		stderrText: "",
		...overrides,
	};
}

function requireControl(condition: boolean, detail: string): void {
	if (!condition)
		throw new Error(`verdict control failed: ${detail}`);
}

function evaluateLeaf(actual: StageObservation): LeafEvaluation {
	const stage = decideStage("leaf", 0, actual, expectedZero, expectedOutput);
	const procedure = finishProcedure(["leaf"], [stage]);
	return {ok: stage.ok, reasons: procedure.failures, exitStatus: procedure.exitStatus};
}

function runControls(): void {
	const evidence: ControlEvidence[] = [];
	const baseline = evaluateLeaf(observation());
	requireControl(baseline.ok && baseline.exitStatus === 0 && baseline.reasons.length === 0, "complete passing baseline");
	evidence.push({name: "passing-baseline", stageAccepted: baseline.ok, procedureExitStatus: baseline.exitStatus, failures: baseline.reasons, downstreamAttempted: false});

	const expectedDiagnostic = decideStage("baseline-diagnostic", 0, observation({exitStatus: 1, stderrText: "cannot find TiqianArray"}),
		{kind: "diagnostic", stderrIncludes: "TiqianArray"});
	const diagnosticProcedure = finishProcedure(["baseline-diagnostic"], [expectedDiagnostic]);
	requireControl(expectedDiagnostic.ok && diagnosticProcedure.exitStatus === 0, "authored compiler diagnostic is an accepted observation");
	evidence.push({name: "expected-diagnostic", stageAccepted: expectedDiagnostic.ok, procedureExitStatus: diagnosticProcedure.exitStatus,
		failures: diagnosticProcedure.failures, downstreamAttempted: false});

	const correctStdoutNonzero = evaluateLeaf(observation({exitStatus: 1}));
	requireControl(!correctStdoutNonzero.ok && correctStdoutNonzero.exitStatus === 1
		&& correctStdoutNonzero.reasons.some(reason => reason.includes("expected normal child exit 0")), "matching stdout with nonzero exit");
	evidence.push({name: "correct-stdout-nonzero", stageAccepted: correctStdoutNonzero.ok, procedureExitStatus: correctStdoutNonzero.exitStatus,
		failures: correctStdoutNonzero.reasons, downstreamAttempted: false});

	const signaled = evaluateLeaf(observation({outcome: "signaled", exitStatus: null, signal: "SIGTERM"}));
	requireControl(!signaled.ok && signaled.exitStatus === 1
		&& signaled.reasons.some(reason => reason.includes("signaled/null/SIGTERM/true")), "matching stdout then signal");
	evidence.push({name: "correct-stdout-signal", stageAccepted: signaled.ok, procedureExitStatus: signaled.exitStatus,
		failures: signaled.reasons, downstreamAttempted: false});

	const wrongOutput = evaluateLeaf(observation({stdoutText: "different body\n"}));
	requireControl(!wrongOutput.ok && wrongOutput.exitStatus === 1
		&& wrongOutput.reasons.some(reason => reason.includes("stdout did not match")), "incorrect stdout with successful exit");
	evidence.push({name: "wrong-stdout-zero", stageAccepted: wrongOutput.ok, procedureExitStatus: wrongOutput.exitStatus,
		failures: wrongOutput.reasons, downstreamAttempted: false});

	const incomplete = evaluateLeaf(observation({captureComplete: false, evidenceError: "stream write failed"}));
	requireControl(!incomplete.ok && incomplete.exitStatus === 1
		&& incomplete.reasons.some(reason => reason.includes("capture is incomplete")), "incomplete capture");
	evidence.push({name: "incomplete-capture", stageAccepted: incomplete.ok, procedureExitStatus: incomplete.exitStatus,
		failures: incomplete.reasons, downstreamAttempted: false});

	const macro = decideStage("macro-probe", 0, observation({exitStatus: 1}), expectedZero, expectedOutput);
	const decisions = [macro];
	const downstreamAttempted = macro.ok;
	if (downstreamAttempted)
		decisions.push(decideStage("gen-swift", 0, observation(), expectedZero));
	const macroProcedure = finishProcedure(["macro-probe", "gen-swift"], decisions);
	requireControl(!downstreamAttempted && macroProcedure.exitStatus === 1
		&& macroProcedure.failures.some(reason => reason.includes("macro-probe: expected normal child exit 0"))
		&& macroProcedure.failures.some(reason => reason.includes("gen-swift: mandatory stage was not attempted")),
		"failed macro blocks downstream stages and fails the procedure");
	evidence.push({name: "macro-failure-blocks-consumer", stageAccepted: macro.ok, procedureExitStatus: macroProcedure.exitStatus,
		failures: macroProcedure.failures, downstreamAttempted});

	console.log(JSON.stringify(evidence, null, 2));
}

runControls();
