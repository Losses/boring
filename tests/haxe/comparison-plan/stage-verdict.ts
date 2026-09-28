export type ExpectedChildResult =
	| { kind: "zero" }
	| { kind: "diagnostic"; stderrIncludes: string };

export type StageObservation = {
	outcome: string | null;
	exitStatus: number | null;
	signal: string | null;
	captureComplete: boolean;
	evidenceError: string | null;
	stdoutAvailable: boolean;
	stderrAvailable: boolean;
	recordAvailable: boolean;
	stdoutArchiveAvailable: boolean;
	stderrArchiveAvailable: boolean;
	stdoutText: string;
	stderrText: string;
};

export type StageDecision = {
	stage: string;
	ok: boolean;
	observed: string;
	reasons: string[];
};

export type ProcedureDecision = {
	exitStatus: 0 | 1;
	failures: string[];
};

export function decideStage(stage: string, probeExitCode: number | null, observation: StageObservation | null,
	expected: ExpectedChildResult, expectedOutput?: string): StageDecision {
	const reasons: string[] = [];
	if (probeExitCode !== 0)
		reasons.push(`${stage}: EvidenceProbe exit was ${probeExitCode ?? "unavailable"}, expected 0`);
	if (observation == null) {
		reasons.push(`${stage}: EvidenceProbe returned no usable report`);
		return {stage, ok: false, observed: "probe-invalid", reasons};
	}
	const observed = `${observation.outcome ?? "unknown"}/${observation.exitStatus ?? "null"}/${observation.signal ?? "null"}/${observation.captureComplete}`;
	if (observation.evidenceError != null)
		reasons.push(`${stage}: evidence capture error: ${observation.evidenceError}`);
	if (!observation.captureComplete)
		reasons.push(`${stage}: child capture is incomplete`);
	if (!observation.stdoutAvailable)
		reasons.push(`${stage}: child stdout is unavailable`);
	if (!observation.stderrAvailable)
		reasons.push(`${stage}: child stderr is unavailable`);
	if (!observation.recordAvailable)
		reasons.push(`${stage}: child evidence record is unavailable`);
	if (observation.stdoutAvailable && !observation.stdoutArchiveAvailable)
		reasons.push(`${stage}: captured stdout artifact is unavailable`);
	if (observation.stderrAvailable && !observation.stderrArchiveAvailable)
		reasons.push(`${stage}: captured stderr artifact is unavailable`);
	if (expected.kind === "zero") {
		if (observation.outcome !== "normal-exit" || observation.exitStatus !== 0 || observation.signal != null)
			reasons.push(`${stage}: expected normal child exit 0, observed ${observed}`);
	} else {
		if (observation.outcome !== "normal-exit" || observation.exitStatus == null || observation.exitStatus === 0 || observation.signal != null)
			reasons.push(`${stage}: expected normal nonzero diagnostic exit, observed ${observed}`);
		if (!observation.stderrText.includes(expected.stderrIncludes))
			reasons.push(`${stage}: expected diagnostic was absent from child stderr`);
	}
	if (expectedOutput != null && observation.stdoutText !== expectedOutput)
		reasons.push(`${stage}: child stdout did not match the authored expectation`);
	return {stage, ok: reasons.length === 0, observed, reasons};
}

export function finishProcedure(expectedStages: string[], decisions: StageDecision[], extraFailures: string[] = []): ProcedureDecision {
	const failures = extraFailures.slice();
	const names = new Set(expectedStages);
	for (const decision of decisions) {
		if (!names.has(decision.stage))
			failures.push(`${decision.stage}: undeclared stage`);
		failures.push(...decision.reasons);
		if (!decision.ok && decision.reasons.length === 0)
			failures.push(`${decision.stage}: stage failed without a recorded reason`);
	}
	for (const stage of names) {
		const count = decisions.filter(decision => decision.stage === stage).length;
		if (count === 0)
			failures.push(`${stage}: mandatory stage was not attempted`);
		else if (count > 1)
			failures.push(`${stage}: mandatory stage was attempted ${count} times`);
	}
	return {exitStatus: failures.length === 0 ? 0 : 1, failures};
}
