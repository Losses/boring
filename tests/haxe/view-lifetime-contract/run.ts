// Thin typed orchestrator of the view-lifetime-contract fixture. It invokes
// the existing EvidenceProbe (no new spawn/capture implementation), retains
// the raw probe output and the child record, and validates the structured
// result. A stage passes only when the probe itself exited normally, a
// record is present, the child exited normally with status 0, capture is
// complete, no evidence or capture error is recorded, and both raw stream
// files exist. Missing evidence fails with a retained diagnostic; it is
// never replaced by an empty file representing a successful capture.

import * as fs from "node:fs";
import * as path from "node:path";
import { spawnSync } from "bun";

interface ViewLifetimeProbePlan {
	mode: string;
	projectPath: string;
	evidenceParent: string;
	maxBufferBytes: number;
	bundle: string;
	action: string;
	step: string;
	cmd: string;
	args: string[];
	cwd: string;
	overrides: null;
}

interface ViewLifetimeChildRecord {
	outcome: string;
	exitStatus: number | null;
	signal: string | null;
	launchError: string | null;
	stdoutAvailable: boolean;
	stderrAvailable: boolean;
	stdoutPath: string | null;
	stderrPath: string | null;
	childDirectory: string;
	captureComplete: boolean;
	captureError: string | null;
	sequence: number;
	bundle: string;
	action: string;
	step: string;
}

interface ViewLifetimeProbeReport {
	evidenceError: string | null;
	evidenceDetail: string | null;
	outcome: string | null;
	exitStatus: number | null;
	signal: string | null;
	launchError: string | null;
	captureComplete: boolean | null;
	captureError: string | null;
	stdoutAvailable: boolean | null;
	stderrAvailable: boolean | null;
	succeeded: boolean;
	stdoutText: string;
	stderrText: string;
	childDirectory: string | null;
	sequence: number | null;
	record: ViewLifetimeChildRecord | null;
}

interface ViewLifetimeStageVerification {
	stage: string;
	probeExitCode: number | null;
	probeSucceeded: boolean;
	evidenceErrorIsAbsent: boolean;
	recordIsPresent: boolean;
	outcome: string | null;
	exitStatus: number | null;
	captureComplete: boolean | null;
	captureErrorIsAbsent: boolean | null;
	stdoutStreamExists: boolean | null;
	stderrStreamExists: boolean | null;
	passed: boolean;
}

const MAX_BUFFER_BYTES = 16777216;
const BUNDLE = "view-lifetime-contract";
const ACTION = "check";

function fail(message: string): never {
	console.error(`view-lifetime-orchestrator: ${message}`);
	process.exit(2);
}

function main(): void {
	const argv: string[] = process.argv.slice(2);
	if (argv.length < 4) {
		fail("usage: bun run.ts <probe-js> <run-dir> <stage-id> <cmd> [args...]");
	}
	const probeJs: string = argv[0];
	const runDir: string = path.resolve(argv[1]);
	const stage: string = argv[2];
	const cmd: string = argv[3];
	const args: string[] = argv.slice(4);
	const root: string = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../../..");
	// The module reads one file as the project content identity (the bundle
	// driver uses the project manifest); the repository manifest is the
	// identity file of this checkout.
	const projectIdentity: string = path.join(root, "boring.json");
	if (!fs.existsSync(projectIdentity)) {
		fail(`project identity file missing: ${projectIdentity}`);
	}
	const stageDir: string = path.join(runDir, "stages", stage);
	const evidenceParent: string = path.join(runDir, "evidence", stage);
	fs.mkdirSync(stageDir, { recursive: true });
	fs.mkdirSync(evidenceParent, { recursive: true });

	const plan: ViewLifetimeProbePlan = {
		mode: "capture",
		projectPath: projectIdentity,
		evidenceParent,
		maxBufferBytes: MAX_BUFFER_BYTES,
		bundle: BUNDLE,
		action: ACTION,
		step: stage,
		cmd,
		args,
		cwd: root,
		overrides: null,
	};
	const planPath: string = path.join(stageDir, "plan.json");
	fs.writeFileSync(planPath, JSON.stringify(plan, null, 2) + "\n");

	const probe = spawnSync({ cmd: ["bun", probeJs, planPath], cwd: root, stdout: "pipe", stderr: "pipe" });
	fs.writeFileSync(path.join(stageDir, "probe-raw-stdout.txt"), probe.stdout);
	fs.writeFileSync(path.join(stageDir, "probe-raw-stderr.txt"), probe.stderr);
	fs.writeFileSync(path.join(stageDir, "probe-status.txt"), String(probe.exitCode ?? -1) + "\n");

	let report: ViewLifetimeProbeReport;
	try {
		report = JSON.parse(probe.stdout.toString()) as ViewLifetimeProbeReport;
	} catch (problem) {
		fail(`stage ${stage}: the probe did not print a JSON report: ${String(problem)}`);
	}
	fs.writeFileSync(path.join(stageDir, "report.json"), JSON.stringify(report, null, 2) + "\n");

	const record: ViewLifetimeChildRecord | null = report.record;
	let stdoutStreamExists: boolean | null = null;
	let stderrStreamExists: boolean | null = null;
	if (record != null) {
		fs.copyFileSync(path.join(record.childDirectory, "record.json"), path.join(stageDir, "child-record.json"));
		stdoutStreamExists = record.stdoutPath != null && fs.existsSync(record.stdoutPath);
		stderrStreamExists = record.stderrPath != null && fs.existsSync(record.stderrPath);
		if (record.stdoutPath != null && stdoutStreamExists) {
			fs.copyFileSync(record.stdoutPath, path.join(stageDir, "child-stdout.txt"));
		} else {
			fs.writeFileSync(
				path.join(stageDir, "child-stdout-missing.json"),
				JSON.stringify({ expectedPath: record.stdoutPath, exists: stdoutStreamExists }, null, 2) + "\n",
			);
		}
		if (record.stderrPath != null && stderrStreamExists) {
			fs.copyFileSync(record.stderrPath, path.join(stageDir, "child-stderr.txt"));
		} else {
			fs.writeFileSync(
				path.join(stageDir, "child-stderr-missing.json"),
				JSON.stringify({ expectedPath: record.stderrPath, exists: stderrStreamExists }, null, 2) + "\n",
			);
		}
	}

	const verification: ViewLifetimeStageVerification = {
		stage,
		probeExitCode: probe.exitCode ?? null,
		probeSucceeded: probe.exitCode === 0,
		evidenceErrorIsAbsent: report.evidenceError == null,
		recordIsPresent: record != null,
		outcome: record == null ? report.outcome : record.outcome,
		exitStatus: record == null ? report.exitStatus : record.exitStatus,
		captureComplete: record == null ? report.captureComplete : record.captureComplete,
		captureErrorIsAbsent: record == null ? null : record.captureError == null,
		stdoutStreamExists,
		stderrStreamExists,
		passed: false,
	};
	verification.passed =
		verification.probeSucceeded &&
		verification.recordIsPresent &&
		verification.evidenceErrorIsAbsent &&
		verification.outcome === "normal-exit" &&
		verification.exitStatus === 0 &&
		verification.captureComplete === true &&
		verification.captureErrorIsAbsent === true &&
		verification.stdoutStreamExists === true &&
		verification.stderrStreamExists === true;
	fs.writeFileSync(path.join(stageDir, "verification.json"), JSON.stringify(verification, null, 2) + "\n");
	console.log(
		`stage ${stage} ${verification.passed ? "zero" : `failure(probe=${verification.probeExitCode} outcome=${verification.outcome} exit=${verification.exitStatus} captureComplete=${verification.captureComplete} stdout=${verification.stdoutStreamExists} stderr=${verification.stderrStreamExists})`} producer=${cmd}`,
	);
	process.exit(verification.passed ? 0 : 1);
}

main();
