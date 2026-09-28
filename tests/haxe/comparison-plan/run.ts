import { mkdirSync, readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { decideStage, finishProcedure, type ExpectedChildResult, type StageDecision, type StageObservation } from "./stage-verdict.ts";

type CapturedChildRecord = {
	stdoutPath: string | null;
	stderrPath: string | null;
	childDirectory: string;
};

type ProbeResult = {
	stdoutText: string;
	stderrText: string;
	outcome: string | null;
	exitStatus: number | null;
	signal: string | null;
	captureComplete: boolean;
	evidenceError: string | null;
	stdoutAvailable: boolean;
	stderrAvailable: boolean;
	record: CapturedChildRecord | null;
};

type EnvironmentOverride = { name: string; value: string };
type EvidenceStagePlan = {
	mode: "capture";
	projectPath: string;
	evidenceParent: string;
	maxBufferBytes: number;
	bundle: string;
	action: string;
	step: string;
	cmd: string;
	args: string[];
	cwd: string;
	overrides: EnvironmentOverride[];
};

const root = process.cwd();
function requiredArgument(index: number, label: string): string {
	const argument = process.argv[index];
	if (argument == null || argument.length === 0)
		throw new Error(`missing required ${label} argument at index ${index}`);
	return argument;
}

const run = resolve(requiredArgument(2, "attempt directory"));
const probe = resolve(requiredArgument(3, "EvidenceProbe path"));
const baselineHxml = resolve(requiredArgument(4, "baseline HXML path"));
const statusPath = join(run, "status.tsv");
const expectedPath = join(run, "expected-stages.txt");
const extraFailures: string[] = [];
const stageDecisions: StageDecision[] = [];
const statusLines = ["stage\texpected\tobserved\tproducer"];
const cases = ["int-ordinary", "int-extremes", "array-order", "nullable-order", "string-order", "nullable-int-order", "mixed-sign-array-order", "shared-enum-helpers", "same-short-record-helpers", "parameter-composition"];
const declaredStages = ["macro-probe", "gen-swift", "swiftc-library", "swiftc-harness", ...cases.map(name => `run-swift-${name}`),
	"gen-static-table", "gen-static-table-baseline", "swiftc-static-table-baseline", "swiftc-static-table", "run-static-table"];
const attemptedStages: string[] = [];
let failedAt: string | null = null;
const declaredStageText = declaredStages.join("\n") + "\n";
if (readFileSync(expectedPath, "utf8") !== declaredStageText)
	extraFailures.push("authored stage declaration did not match the runner's mandatory stages");

function write(path: string, content: string | Uint8Array): void {
	writeFileSync(path, content);
}

function stagePlan(stage: string, command: string, args: string[], projectPath: string, overrides: EnvironmentOverride[] = []): EvidenceStagePlan {
	return {
		mode: "capture",
		projectPath,
		evidenceParent: join(run, "children"),
		maxBufferBytes: 16777216,
		bundle: "boring-a3-comparison-plan",
		action: "focused-swift",
		step: stage,
		cmd: command,
		args,
		cwd: root,
		overrides,
	};
}

async function capture(stage: string, command: string, args: string[], projectPath: string, expectedOutput?: string,
	overrides: EnvironmentOverride[] = [], expectedResult: ExpectedChildResult = {kind: "zero"}): Promise<boolean> {
	attemptedStages.push(stage);
	const stageDir = join(run, "stages", stage);
	mkdirSync(stageDir, {recursive: true});
	const planPath = join(run, "plans", `${stage}.json`);
	const plan = stagePlan(stage, command, args, projectPath, overrides);
	write(planPath, JSON.stringify(plan, null, 2) + "\n");
	write(join(stageDir, "argv.json"), JSON.stringify({command, args, cwd: root, planPath}, null, 2) + "\n");
	const called = Bun.spawnSync(["bun", probe, planPath], {cwd: root, stdout: "pipe", stderr: "pipe"});
	const probeOut = called.stdout.toString();
	const probeErr = called.stderr.toString();
	write(join(stageDir, "probe-stdout.jsonl"), probeOut);
	write(join(stageDir, "probe-stderr.txt"), probeErr);
	write(join(stageDir, "probe-status.txt"), `${called.exitCode ?? 128}\n`);
	let report: ProbeResult | null = null;
	try {
		const decoded: unknown = JSON.parse(probeOut);
		if (isProbeResult(decoded))
			report = decoded;
	} catch {
		// The stage decision below records the unusable probe result.
	}
	if (report != null) {
		write(join(stageDir, "child-report.json"), JSON.stringify(report, null, 2) + "\n");
		if (expectedOutput != null) {
			write(join(stageDir, "expected-output.txt"), expectedOutput);
			write(join(stageDir, "observed-output.txt"), report.stdoutText);
		}
	}
	let archiveError: string | null = null;
	let stdoutArchiveAvailable = false;
	let stderrArchiveAvailable = false;
	if (report?.record?.stdoutPath != null) {
		try {
			copyFileSync(report.record.stdoutPath, join(stageDir, "child-stdout.bin"));
			stdoutArchiveAvailable = true;
		} catch (error) {
			archiveError = `could not archive child stdout: ${String(error)}`;
		}
	}
	if (report?.record?.stderrPath != null) {
		try {
			copyFileSync(report.record.stderrPath, join(stageDir, "child-stderr.bin"));
			stderrArchiveAvailable = true;
		} catch (error) {
			archiveError = `could not archive child stderr: ${String(error)}`;
		}
	}
	const observation:StageObservation | null = report == null ? null : {
		...report,
		evidenceError: archiveError ?? report.evidenceError,
		recordAvailable: report.record != null,
		stdoutArchiveAvailable,
		stderrArchiveAvailable,
	};
	const decision = decideStage(stage, called.exitCode, observation, expectedResult, expectedOutput);
	stageDecisions.push(decision);
	statusLines.push(`${stage}\t${expectedResult.kind}\t${decision.observed}\t${stage}`);
	if (!decision.ok && failedAt == null)
		failedAt = stage;
	return decision.ok;
}

function isProbeResult(value: unknown): value is ProbeResult {
	if (typeof value !== "object" || value == null)
		return false;
	const candidate = value as Record<string, unknown>;
	return typeof candidate.stdoutText === "string"
		&& typeof candidate.stderrText === "string"
		&& (typeof candidate.outcome === "string" || candidate.outcome === null)
		&& (typeof candidate.exitStatus === "number" || candidate.exitStatus === null)
		&& (typeof candidate.signal === "string" || candidate.signal === null)
		&& typeof candidate.captureComplete === "boolean"
		&& (typeof candidate.evidenceError === "string" || candidate.evidenceError === null)
		&& typeof candidate.stdoutAvailable === "boolean"
		&& typeof candidate.stderrAvailable === "boolean"
		&& (candidate.record == null || isCapturedChildRecord(candidate.record));
}

function isCapturedChildRecord(value: unknown): value is CapturedChildRecord {
	if (typeof value !== "object" || value == null)
		return false;
	const candidate = value as Record<string, unknown>;
	return (typeof candidate.stdoutPath === "string" || candidate.stdoutPath === null)
		&& (typeof candidate.stderrPath === "string" || candidate.stderrPath === null)
		&& typeof candidate.childDirectory === "string";
}

const haxeSource = "tests/haxe/comparison-runtime-observation/hxml/swift.hxml";
const macroProbe = "tests/haxe/comparison-plan/comparison-plan-probe.hxml";
const macroExpected = readFileSync(join(run, "expected-probe.tsv"), "utf8");
const macroOk = await capture("macro-probe", "haxe", [macroProbe], macroProbe, macroExpected);
const gen = join(run, "swift-gen");
const genOk = macroOk && await capture("gen-swift", "haxe", [haxeSource, "-D", `swift-output=${gen}`], haxeSource);

if (genOk) {
	const files: string[] = [];
	for await (const path of new Bun.Glob("**/*.swift").scan({cwd: gen, onlyFiles: true}))
		files.push(join(gen, path));
	files.sort();
	const build = join(run, "build-swift");
	mkdirSync(build, {recursive: true});
	const library = join(build, "libCmpObs.so");
	const loader = process.env.BORING_SWIFT_DYNAMIC_LINKER == null
		? []
		: ["-Xlinker", "-dynamic-linker", "-Xlinker", process.env.BORING_SWIFT_DYNAMIC_LINKER];
	const libArgs = ["-emit-library", "-emit-module", ...loader, ...files, "-module-name", "CmpObs", "-o", library];
	const libOk = await capture("swiftc-library", "swiftc", libArgs, haxeSource);
	if (libOk) {
		const harness = "tests/haxe/comparison-runtime-observation/native/main.swift";
		const binary = join(build, "runner");
		const harnessOk = await capture("swiftc-harness", "swiftc", [...loader, harness, "-I", build, "-L", build, "-lCmpObs", "-o", binary], harness);
		if (harnessOk) {
			const expected = new Map<string, string>();
			for (const line of readFileSync(join(run, "expected-observations.tsv"), "utf8").trimEnd().split("\n")) {
				const [name, body] = line.split("\t", 3);
				if (name != null && body != null)
					expected.set(name, body);
			}
			const env = `LD_LIBRARY_PATH=${build}:${process.env.BORING_SWIFT_LIBDISPATCH ?? ""}`;
			for (const name of cases) {
				const body = expected.get(name);
				if (body == null) {
					extraFailures.push(`missing authored expected observation for ${name}`);
					continue;
				}
				await capture(`run-swift-${name}`, "env", [env, binary, name], harness, body + "\n");
			}
		}
	}
}

if (genOk) {
	const tableHxml = "tests/haxe/swift-runtime-closure/static-data-array-only.hxml";
	const tableGen = join(run, "static-table-gen");
	const tableGenOk = await capture("gen-static-table", "haxe", [tableHxml, "-D", `swift-output=${tableGen}`], tableHxml);
	const baselineGen = join(run, "static-table-baseline-gen");
	const baselineGenOk = await capture("gen-static-table-baseline", "haxe", [baselineHxml, "-D", `swift-output=${baselineGen}`], baselineHxml);
	if (baselineGenOk) {
		const baselineFiles: string[] = [];
		for await (const path of new Bun.Glob("**/*.swift").scan({cwd: baselineGen, onlyFiles: true}))
			baselineFiles.push(join(baselineGen, path));
		baselineFiles.sort();
		const nativeHarness = "tests/haxe/swift-runtime-closure/native-static-data-array-only.swift";
		await capture("swiftc-static-table-baseline", "swiftc", [...baselineFiles, nativeHarness, "-o", join(run, "static-table-baseline-check")], nativeHarness,
			undefined, [], {kind: "diagnostic", stderrIncludes: "TiqianArray"});
	}
	if (tableGenOk) {
		const files: string[] = [];
		for await (const path of new Bun.Glob("**/*.swift").scan({cwd: tableGen, onlyFiles: true}))
			files.push(join(tableGen, path));
		files.sort();
		const binary = join(run, "static-table-check");
		const nativeHarness = "tests/haxe/swift-runtime-closure/native-static-data-array-only.swift";
		const swiftOk = await capture("swiftc-static-table", "swiftc", [...files, nativeHarness, "-o", binary], nativeHarness);
		if (swiftOk)
			await capture("run-static-table", binary, [], nativeHarness, "65\n");
	}
}


	for (const stage of declaredStages) {
	if (!attemptedStages.includes(stage))
		statusLines.push(`${stage}\tnot-reached\tproducer-${failedAt ?? "probe-compile"}\t${failedAt ?? "probe-compile"}`);
}

write(statusPath, statusLines.join("\n") + "\n");
const procedure = finishProcedure(declaredStages, stageDecisions, extraFailures);
write(join(run, "findings.txt"), procedure.failures.length === 0 ? "none\n" : procedure.failures.join("\n") + "\n");
if (procedure.exitStatus !== 0) {
	console.error(procedure.failures.join("\n"));
	process.exit(procedure.exitStatus);
}
