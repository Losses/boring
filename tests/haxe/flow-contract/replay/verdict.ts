// Interpretation owner of the flow contract replay verdict.
//
// One module owns every decision the caller makes over captured results: it
// serializes stage results, judges one captured child, classifies native
// diagnostics against the declared observations, compares an output sequence
// against the authored expectations, and reaches a terminal decision for every
// declared stage. Shell code calls this module and holds none of those rules.
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";

type StageState = "ok" | "failed" | "invalid" | "not-reached" | "unavailable" | "changed";
type StageKind = "producer" | "observation" | "check";
type ObservationState = "unmatched" | "matched";

interface StageDeclaration {
    id: string;
    kind: StageKind;
    observation: string | null;
    dependsOn: string[];
    observes: string[];
}

interface KnownObservation {
    observation: string;
    stage: string;
    category: string | null;
    source: string | null;
    sourceLine: number | null;
    line: string | null;
    expected: string | null;
    observed: string | null;
}

interface Manifest {
    stages: StageDeclaration[];
    knownObservations: KnownObservation[];
}

interface StageRecord {
    stage: string;
    state: StageState;
    detail: string;
}

interface ProbeReport {
    outcome: string;
    exitStatus: number | null;
    signal: string | null;
    captureComplete: boolean;
    evidenceError: string | null;
    captureError: string | null;
    stdoutAvailable: boolean;
    stderrAvailable: boolean;
    stdoutText: string;
    stderrText: string;
    childDirectory: string | null;
}

interface Verdict {
    state: StageState;
    capture: string[];
    child: string[];
}

interface Finding {
    stage: string;
    reason: string;
}

interface ReadResult {
    value: unknown;
    problem: string | null;
}

interface RecordsResult {
    records: StageRecord[];
    problem: string | null;
}

type ReportOf = (stage: string) => ProbeReport | null;

interface LineReplacement {
    index: number;
    from: string;
    to: string;
}

interface Comparison {
    agreements: number;
    observations: string[];
    unexpected: Finding[];
}

interface StoredComparison extends Comparison {
    comparisonStage: string;
    membershipStage: string;
    unexpectedFailures: number;
}

/** Narrows one parsed value to the report shape the probe writes. */
function asReport(value: unknown): ProbeReport | null {
    if (typeof value !== "object" || value === null) {
        return null;
    }
    const r = value as Record<string, unknown>;
    const text = (name: string): string | null => {
        const v = r[name];
        return typeof v === "string" ? v : null;
    };
    const flag = (name: string): boolean => typeof r[name] === "boolean" ? (r[name] as boolean) : false;
    const number = (name: string): number | null => typeof r[name] === "number" ? (r[name] as number) : null;
    return {
        outcome: text("outcome") ?? "unknown",
        exitStatus: number("exitStatus"),
        signal: text("signal"),
        captureComplete: flag("captureComplete"),
        evidenceError: text("evidenceError"),
        captureError: text("captureError"),
        stdoutAvailable: flag("stdoutAvailable"),
        stderrAvailable: flag("stderrAvailable"),
        stdoutText: text("stdoutText") ?? "",
        stderrText: text("stderrText") ?? "",
        childDirectory: text("childDirectory"),
    };
}

/** Narrows one parsed value to a verdict. */
function asVerdict(value: unknown): Verdict | null {
    if (typeof value !== "object" || value === null) {
        return null;
    }
    const r = value as Record<string, unknown>;
    const state = r.state;
    if (typeof state !== "string"
        || !(state === "ok" || state === "failed" || state === "invalid" || state === "not-reached"
            || state === "unavailable" || state === "changed")) {
        return null;
    }
    const capture = stringList(r.capture);
    const child = stringList(r.child);
    return { state: state as StageState, capture, child };
}

interface ManifestResult {
    manifest: Manifest | null;
    problem: string | null;
}

/** Narrows one parsed value to a declared manifest, naming what is wrong. */
function asManifest(value: unknown): ManifestResult {
    if (typeof value !== "object" || value === null) {
        return { manifest: null, problem: "the manifest is not an object" };
    }
    const r = value as Record<string, unknown>;
    if (!Array.isArray(r.stages)) {
        return { manifest: null, problem: "the manifest holds no stage list" };
    }
    const stages: StageDeclaration[] = [];
    let index = 0;
    for (const raw of r.stages) {
        index += 1;
        if (typeof raw !== "object" || raw === null) {
            return { manifest: null, problem: "stage " + index + " is not an object" };
        }
        const s = raw as Record<string, unknown>;
        const id = typeof s.id === "string" ? s.id : null;
        const kind = s.kind === "producer" || s.kind === "observation" || s.kind === "check" ? s.kind : null;
        if (id === null || kind === null) {
            return { manifest: null, problem: "stage " + index + " carries no id or no known kind" };
        }
        stages.push({
            id,
            kind,
            observation: typeof s.observation === "string" ? s.observation : null,
            dependsOn: stringList(s.dependsOn),
            observes: stringList(s.observes),
        });
    }
    const observations: KnownObservation[] = [];
    if (Array.isArray(r.knownObservations)) {
        for (const raw of r.knownObservations) {
            if (typeof raw !== "object" || raw === null) {
                return { manifest: null, problem: "a known observation is not an object" };
            }
            const o = raw as Record<string, unknown>;
            const name = typeof o.observation === "string" ? o.observation : null;
            const stage = typeof o.stage === "string" ? o.stage : null;
            const expected = typeof o.expected === "string" ? o.expected : null;
            const observed = typeof o.observed === "string" ? o.observed : null;
            if (name === null || stage === null) {
                return { manifest: null, problem: "a known observation carries no name or no stage" };
            }
            if ((expected === null) !== (observed === null)) {
                return { manifest: null, problem: "the known observation " + name + " declares its line difference incompletely" };
            }
            const diagnostic = typeof o.category === "string" && typeof o.source === "string" && typeof o.sourceLine === "number";
            if (!diagnostic && expected === null) {
                return { manifest: null, problem: "the known observation " + name + " declares neither a diagnostic nor a line difference" };
            }
            const category = typeof o.category === "string" ? o.category : null;
            const source = typeof o.source === "string" ? o.source : null;
            const sourceLine = typeof o.sourceLine === "number" ? o.sourceLine : null;
            if ((category === null) !== (source === null) || (category === null) !== (sourceLine === null)) {
                return { manifest: null, problem: "the known observation " + String(name ?? "?") + " declares its diagnostic incompletely" };
            }
            const outputLine = typeof o.line === "string" ? o.line : null;
            if ((expected === null) !== (outputLine === null)) {
                return { manifest: null, problem: "the known observation " + String(name ?? "?") + " declares its line difference incompletely" };
            }
            observations.push({
                observation: name,
                stage,
                category,
                source,
                sourceLine,
                line: outputLine,
                expected,
                observed,
            });
        }
    }
    return { manifest: { stages, knownObservations: observations }, problem: null };
}

function stringList(value: unknown): string[] {
    if (!Array.isArray(value)) {
        return [];
    }
    const out: string[] = [];
    for (const entry of value) {
        if (typeof entry === "string") {
            out.push(entry);
        }
    }
    return out;
}

/** Reads and parses one JSON file, answering null with the parse problem. */
function readJson(path: string): ReadResult {
    if (!existsSync(path)) {
        return { value: null, problem: "the file is missing" };
    }
    const text = readFileSync(path, "utf8");
    if (text.trim().length === 0) {
        return { value: null, problem: "the file is empty" };
    }
    try {
        return { value: JSON.parse(text), problem: null };
    } catch (problem) {
        const message = problem instanceof Error ? problem.message : String(problem);
        return { value: null, problem: "the file is not valid JSON: " + message };
    }
}

/** Judges one captured child from its probe report and the probe's own exit. */
export function judge(report: ProbeReport | null, readProblem: string | null, probeExit: number): Verdict {
    const capture: string[] = [];
    const child: string[] = [];
    if (readProblem !== null || report === null) {
        capture.push(readProblem ?? "the report could not be read");
        return { state: "invalid", capture, child };
    }
    if (probeExit !== 0) {
        capture.push("the probe exited with " + probeExit);
    }
    if (report.evidenceError !== null) {
        capture.push("evidenceError: " + report.evidenceError);
    }
    if (report.captureComplete !== true) {
        capture.push("captureComplete is " + report.captureComplete);
    }
    if (report.captureError !== null) {
        capture.push("captureError: " + report.captureError);
    }
    if (report.stdoutAvailable !== true) {
        capture.push("the stdout stream is not available");
    }
    if (report.stderrAvailable !== true) {
        capture.push("the stderr stream is not available");
    }
    if (capture.length > 0) {
        return { state: "invalid", capture, child };
    }
    if (report.outcome !== "normal-exit") {
        child.push("outcome is " + report.outcome + (report.signal === null ? "" : " (" + report.signal + ")"));
    }
    if (report.exitStatus !== 0) {
        child.push("child exitStatus is " + report.exitStatus);
    }
    return { state: child.length > 0 ? "failed" : "ok", capture, child };
}

/** One native diagnostic line: its category, its source location and its text. */
interface Diagnostic {
    file: string;
    line: number;
    severity: string;
    text: string;
}

/** Reads the native diagnostics of one compiler stream. */
function diagnosticsOf(text: string): Diagnostic[] {
    const out: Diagnostic[] = [];
    for (const line of text.split("\n")) {
        const match = /^(.+\.kt):(\d+):\d+: (error|warning): (.*)$/.exec(line);
        if (match === null) {
            continue;
        }
        out.push({ file: match[1] ?? "", line: Number(match[2] ?? "0"), severity: match[3] ?? "", text: match[4] ?? "" });
    }
    return out;
}

/** Whether one capture matches one declared native observation exactly. */
function matchesObservation(verdict: Verdict, report: ProbeReport, observation: KnownObservation): ObservationState {
    if (verdict.state !== "failed" || verdict.capture.length > 0) {
        return "unmatched";
    }
    if (observation.category === null || observation.source === null || observation.sourceLine === null) {
        return "unmatched";
    }
    if (report.exitStatus !== 1 || report.outcome !== "normal-exit") {
        return "unmatched";
    }
    const errors = diagnosticsOf(report.stderrText).filter(d => d.severity === "error");
    if (errors.length !== 1) {
        return "unmatched";
    }
    const only = errors[0];
    if (only === undefined) {
        return "unmatched";
    }
    if (!only.file.endsWith(observation.source) || only.line !== observation.sourceLine) {
        return "unmatched";
    }
    if (only.text !== observation.category) {
        return "unmatched";
    }
    return "matched";
}

/**
 * Compares one measured sequence against the authored sequence. The measured
 * sequence is accepted only when it is the authored sequence, or when it is the
 * authored sequence with exactly one documented replacement at the
 * replacement's own index. A missing, duplicated, reordered or additional line
 * is never accepted.
 */
interface SequenceVerdict {
    accepted: boolean;
    agreements: number;
    /** How many lines actually carry the documented replacement. */
    replaced: number;
    problem: string | null;
}

function compareSequence(expected: string[], actual: string[], replacement: LineReplacement | null): SequenceVerdict {
    if (actual.length !== expected.length) {
        return {
            accepted: false,
            agreements: 0,
            replaced: 0,
            problem: "the measured sequence holds " + actual.length + " lines against " + expected.length + " authored lines",
        };
    }
    let replaced = 0;
    let agreements = 0;
    let problem: string | null = null;
    for (let index = 0; index < expected.length; index += 1) {
        const want = expected[index] ?? "";
        const have = actual[index] ?? "";
        if (want === have) {
            agreements += 1;
            continue;
        }
        const documented = replacement !== null && replacement.index === index && replacement.from === want && replacement.to === have;
        if (!documented) {
            problem = problem === null ? "line " + (index + 1) + " is " + JSON.stringify(have) + " against " + JSON.stringify(want) : problem;
            continue;
        }
        replaced += 1;
    }
    if (replaced > 1) {
        return { accepted: false, agreements: 0, replaced, problem: "more than one line carries the documented replacement" };
    }
    return { accepted: problem === null, agreements, replaced, problem };
}

/** Serializes one stage record so the line stays valid JSON. */
function stageLine(record: StageRecord): string {
    return JSON.stringify(record);
}

/** Reads the stage records of one attempt. */
function readRecords(path: string): RecordsResult {
    if (!existsSync(path)) {
        return { records: [], problem: "the stage result table is missing" };
    }
    const records: StageRecord[] = [];
    const problems: string[] = [];
    const lines = readFileSync(path, "utf8").split("\n");
    for (let index = 0; index < lines.length; index += 1) {
        const line = lines[index] ?? "";
        if (line.trim().length === 0) {
            continue;
        }
        let parsed: unknown;
        try {
            parsed = JSON.parse(line);
        } catch (problem) {
            const message = problem instanceof Error ? problem.message : String(problem);
            problems.push("line " + (index + 1) + " is not valid JSON: " + message);
            continue;
        }
        if (typeof parsed !== "object" || parsed === null) {
            problems.push("line " + (index + 1) + " is not a stage record");
            continue;
        }
        const r = parsed as Record<string, unknown>;
        const stage = typeof r.stage === "string" ? r.stage : null;
        const state = r.state;
        const detail = typeof r.detail === "string" ? r.detail : "";
        if (stage === null || typeof state !== "string"
            || !(state === "ok" || state === "failed" || state === "invalid" || state === "not-reached"
                || state === "unavailable" || state === "changed")) {
            problems.push("line " + (index + 1) + " carries no known stage state");
            continue;
        }
        records.push({ stage, state: state as StageState, detail });
    }
    return { records, problem: problems.length > 0 ? problems.join("; ") : null };
}

/** Reaches a terminal decision for every declared stage of one attempt. */
function evaluate(manifest: Manifest, evaluated: StageDeclaration[], records: StageRecord[], reportOf: ReportOf): Comparison {
    const byId = new Map<string, StageRecord>();
    const duplicates: string[] = [];
    for (const record of records) {
        if (byId.has(record.stage)) {
            duplicates.push(record.stage);
        }
        byId.set(record.stage, record);
    }
    const unexpected: Finding[] = [];
    const observations: string[] = [];
    let agreements = 0;
    for (const duplicate of duplicates) {
        unexpected.push({ stage: duplicate, reason: "more than one recorded result" });
    }
    for (const record of records) {
        if (!manifest.stages.some(stage => stage.id === record.stage)) {
            unexpected.push({ stage: record.stage, reason: "a recorded stage the manifest does not declare" });
        }
    }
    for (const stage of evaluated) {
        const record = byId.get(stage.id);
        if (record === undefined) {
            unexpected.push({ stage: stage.id, reason: "no recorded result" });
            continue;
        }
        if (record.state === "not-reached") {
            const blockers = stage.dependsOn.filter(id => byId.get(id)?.state !== "ok");
            const blockingObservations = blockers.filter(id => {
                const declaration = manifest.stages.find(s => s.id === id);
                return declaration !== undefined && declaration.kind === "observation";
            });
            if (blockers.length > 0 && blockers.length === blockingObservations.length) {
                continue;
            }
            unexpected.push({ stage: stage.id, reason: "not reached" + (blockers.length > 0 ? "; blocked by " + blockers.join(", ") : "") });
            continue;
        }
        if (record.state === "invalid") {
            unexpected.push({ stage: stage.id, reason: "the capture does not hold: " + record.detail });
            continue;
        }
        if (stage.kind === "observation") {
            const observation = manifest.knownObservations.find(o => o.observation === stage.observation);
            if (observation === undefined) {
                unexpected.push({ stage: stage.id, reason: "the stage declares no known observation" });
                continue;
            }
            if (record.state !== "failed") {
                unexpected.push({ stage: stage.id, reason: "the declared observation requires a recorded failure, and the state is " + record.state });
                continue;
            }
            const report = reportOf(stage.id);
            if (report === null) {
                unexpected.push({ stage: stage.id, reason: "the probe report of the observed child is missing" });
                continue;
            }
            if (matchesObservation({ state: record.state, capture: [], child: [] }, report, observation) === "matched") {
                observations.push(observation.observation);
                continue;
            }
            unexpected.push({
                stage: stage.id,
                reason: "the recorded failure does not carry the declared diagnostic " + observation.observation
                    + " (" + observation.source + ":" + observation.sourceLine + " " + observation.category + ")",
            });
            continue;
        }
        if (record.state === "ok") {
            agreements += 1;
            continue;
        }
        unexpected.push({ stage: stage.id, reason: "the stage is a " + stage.kind + " and its state is " + record.state + ": " + record.detail });
    }
    return { agreements, observations, unexpected };
}

/** Splits one authored or measured output into its lines. */
function linesOf(text: string): string[] {
    const out: string[] = [];
    for (const line of text.split("\n")) {
        if (line.length > 0) {
            out.push(line);
        }
    }
    return out;
}

function argumentValue(argv: string[], name: string): string | null {
    const index = argv.indexOf(name);
    if (index < 0 || index + 1 >= argv.length) {
        return null;
    }
    return argv[index + 1] ?? null;
}

function fail(message: string): never {
    process.stderr.write(message + "\n");
    process.exit(2);
    throw new Error(message);
}

function main(): void {
    const command = process.argv[2] ?? "";
    const argv = process.argv.slice(3);

    if (command === "judge") {
        const reportPath = argumentValue(argv, "--report");
        const stage = argumentValue(argv, "--stage");
        const results = argumentValue(argv, "--results");
        const states = argumentValue(argv, "--states");
        const probeExit = Number(argumentValue(argv, "--probe-exit") ?? "-1");
        if (reportPath === null || stage === null || results === null || Number.isNaN(probeExit)) {
            fail("judge needs --report, --stage, --results and --probe-exit");
        }
        const read = readJson(reportPath);
        const report = read.problem === null ? asReport(read.value) : null;
        const verdict = judge(report, read.problem, probeExit);
        writeFileSync(reportPath.replace(/\.json$/, ".verdict.json"), JSON.stringify(verdict, null, 2) + "\n");
        appendFileSync(results, stageLine({ stage, state: verdict.state, detail: verdict.capture.concat(verdict.child).join("; ") }) + "\n");
        if (states !== null) {
            appendFileSync(states, stage + "\t" + verdict.state + "\n");
        }
        process.stdout.write(JSON.stringify(verdict) + "\n");
        process.exit(0);
    }

    if (command === "stage-line") {
        const stage = argumentValue(argv, "--stage");
        const state = argumentValue(argv, "--state");
        const detail = argumentValue(argv, "--detail");
        const results = argumentValue(argv, "--results");
        const states = argumentValue(argv, "--states");
        if (stage === null || state === null || results === null) {
            fail("stage-line needs --stage, --state and --results");
        }
        appendFileSync(results, stageLine({ stage, state: state as StageState, detail: detail ?? "" }) + "\n");
        if (states !== null) {
            appendFileSync(states, stage + "\t" + state + "\n");
        }
        process.exit(0);
    }

    if (command === "state") {
        const path = argumentValue(argv, "--verdict");
        if (path === null) {
            fail("state needs --verdict");
        }
        const read = readJson(path);
        const verdict = read.problem === null ? asVerdict(read.value) : null;
        if (verdict === null) {
            fail("the verdict file is unusable: " + (read.problem ?? "no state"));
        }
        process.stdout.write(verdict.state + "\n");
        process.exit(0);
    }

    if (command === "stage-ids") {
        const manifestPath = argumentValue(argv, "--manifest");
        const resultsPath = argumentValue(argv, "--results");
        const outDir = argumentValue(argv, "--out");
        const excludeRaw = argumentValue(argv, "--exclude");
        if (manifestPath === null || resultsPath === null || outDir === null) {
            fail("stage-ids needs --manifest, --results and --out");
        }
        const manifestRead = readJson(manifestPath);
        const parsedManifest = asManifest(manifestRead.value);
        const manifest = manifestRead.problem === null ? parsedManifest.manifest : null;
        if (manifest === null) {
            fail("the frozen manifest is unusable: " + (manifestRead.problem ?? parsedManifest.problem ?? "no stages"));
        }
        const excluded = stringList(excludeRaw === null ? [] : excludeRaw.split(","));
        for (const id of excluded) {
            if (!manifest.stages.some(stage => stage.id === id)) {
                fail("the excluded stage " + id + " is not declared by the frozen manifest");
            }
        }
        const records = readRecords(resultsPath);
        if (records.problem !== null) {
            fail("the stage result table is unusable: " + records.problem);
        }
        // The expected set is the frozen declaration. The observed table is the
        // recorded table itself: one row per recorded result, in recorded
        // order, so the check sees every missing, duplicated or undeclared
        // stage exactly as the records hold it.
        const expected = manifest.stages.map(s => s.id).filter(id => !excluded.includes(id));
        writeFileSync(outDir + "/expected-stages.txt", expected.join("\n") + "\n");
        writeFileSync(outDir + "/status.tsv",
            "stage\tstate\n" + records.records.map(r => r.stage + "\t" + r.state).join("\n") + "\n");
        // The excluded stage is the membership check itself: its record does
        // not exist when this adapter runs, so the check is a prefix check and
        // the caller must require its recorded result afterwards.
        writeFileSync(outDir + "/scope.txt", "prefix membership over " + records.records.length
            + " recorded results; the expected set is the frozen declaration without "
            + (excluded.length > 0 ? excluded.join(", ") : "no stage")
            + ", whose own record is written after this check\n");
        process.stdout.write("stage identity files written under " + outDir + "\n");
        process.exit(0);
    }

    if (command === "compare") {
        const attempt = argumentValue(argv, "--attempt");
        const replay = argumentValue(argv, "--replay");
        const frozenManifest = argumentValue(argv, "--manifest");
        const exclude = argumentValue(argv, "--exclude");
        if (attempt === null || replay === null || frozenManifest === null) {
            fail("compare needs --attempt, --replay and --manifest");
        }
        const excluded = stringList(exclude === null ? [] : exclude.split(","));
        const manifestRead = readJson(frozenManifest);
        const parsedManifest = asManifest(manifestRead.value);
        const manifest = manifestRead.problem === null ? parsedManifest.manifest : null;
        if (manifest === null) {
            fail("the frozen manifest is unusable: " + (manifestRead.problem ?? parsedManifest.problem ?? "no stages"));
        }
        const records = readRecords(attempt + "/stage-results.jsonl");
        if (records.problem !== null) {
            fail("the stage result table is unusable: " + records.problem);
        }
        const reportOf = (stage: string): ProbeReport | null => {
            const read = readJson(attempt + "/reports/" + stage + ".json");
            return read.problem === null ? asReport(read.value) : null;
        };
        const evaluated = manifest.stages.filter(stage => !excluded.includes(stage.id));
        const comparison = evaluate(manifest, evaluated, records.records, reportOf);

        let verdictLines = "";
        for (const group of ["a", "c"]) {
            const expectedRead = readFileSync(replay + "/expected/group-" + group + ".txt", "utf8");
            const expected = linesOf(expectedRead);
            // The reference run carries the oracle claim of the manifest, so its
            // own stdout is measured against the authored sequence before any
            // target is measured against it.
            for (const target of ["reference", "kotlin", "rust"]) {
                const stage = target === "reference" ? group + "-reference" : group + "-" + target + "-run";
                const declaration = manifest.stages.find(s => s.id === stage);
                const record = records.records.find(r => r.stage === stage);
                if (declaration === undefined || record === undefined) {
                    comparison.unexpected.push({ stage, reason: "no declared stage " + stage + " to measure" });
                    verdictLines += "group " + group + " " + target + ": no declared stage " + stage + " to measure\n";
                    continue;
                }
                if (record.state !== "ok") {
                    verdictLines += "group " + group + " " + target + ": not measured (" + record.state + ")\n";
                    continue;
                }
                const report = reportOf(stage);
                if (report === null) {
                    comparison.unexpected.push({ stage, reason: "the probe report of the run is missing" });
                    verdictLines += "group " + group + " " + target + ": CONFORMANCE FAILURE, the report is missing\n";
                    continue;
                }
                const actual = linesOf(report.stdoutText);
                // The one documented replacement belongs to one target of one
                // group. Every other measured sequence must agree exactly.
                let replacement: LineReplacement | null = null;
                let replacementObservation: string | null = null;
                if (group === "a" && target === "rust") {
                    const declared = manifest.knownObservations.find(o => o.stage === stage);
                    if (declared !== undefined && declared.line !== null && declared.expected !== null
                        && declared.observed !== null) {
                        const from = declared.line + "=" + declared.expected;
                        const index = expected.indexOf(from);
                        if (index < 0) {
                            comparison.unexpected.push({ stage, reason: "the authored sequence holds no documented replacement line" });
                            verdictLines += "group " + group + " " + target
                                + ": CONFORMANCE FAILURE, the authored sequence holds no replacement line\n";
                            continue;
                        }
                        replacement = { index, from, to: declared.line + "=" + declared.observed };
                        replacementObservation = declared.observation;
                    }
                }
                const sequence = compareSequence(expected, actual, replacement);
                if (!sequence.accepted) {
                    comparison.unexpected.push({ stage, reason: sequence.problem ?? "the measured sequence differs from the authored sequence" });
                    verdictLines += "group " + group + " " + target + ": CONFORMANCE FAILURE, " + sequence.problem + "\n";
                    continue;
                }
                comparison.agreements += sequence.agreements;
                // The documented replacement is an observation only when the
                // measured sequence actually carries it. Plain agreement is
                // never reported as nonconformance.
                if (replacement !== null && sequence.replaced === 1) {
                    const name = replacementObservation ?? "";
                    comparison.observations.push(name);
                    verdictLines += "group " + group + " " + target + ": " + sequence.agreements + " of " + expected.length
                        + " lines agree; 1 recorded observation (" + name + ")\n";
                    continue;
                }
                verdictLines += "group " + group + " " + target + ": " + sequence.agreements + " of " + expected.length + " lines agree\n";
            }
        }

        const unexpected = comparison.unexpected.length;
        let text = "";
        for (const finding of comparison.unexpected) {
            text += "UNEXPECTED " + finding.stage + ": " + finding.reason + "\n";
        }
        for (const observation of comparison.observations) {
            text += "RECORDED OBSERVATION " + observation + " (source and target nonconformance, retained)\n";
        }
        text += verdictLines;
        text += "procedure verdict: " + comparison.agreements + " agreements, " + comparison.observations.length
            + " recorded observations, " + unexpected + " unexpected failures\n";
        writeFileSync(attempt + "/comparison.txt", text);
        writeFileSync(attempt + "/comparison.json", JSON.stringify({
            agreements: comparison.agreements,
            observations: comparison.observations,
            unexpected: comparison.unexpected,
        }, null, 2) + "\n");
        process.stdout.write(text);
        process.exit(unexpected > 0 ? 1 : 0);
    }

    if (command === "finalize") {
        const attempt = argumentValue(argv, "--attempt");
        const frozenManifest = argumentValue(argv, "--manifest");
        const comparisonState = argumentValue(argv, "--comparison-state");
        const membershipState = argumentValue(argv, "--membership-state");
        if (attempt === null || frozenManifest === null || comparisonState === null || membershipState === null) {
            fail("finalize needs --attempt, --manifest, --comparison-state and --membership-state");
        }
        const manifestRead = readJson(frozenManifest);
        const parsed = asManifest(manifestRead.value);
        const manifest = manifestRead.problem === null ? parsed.manifest : null;
        if (manifest === null) {
            fail("the frozen manifest is unusable: " + (manifestRead.problem ?? parsed.problem ?? "no stages"));
        }
        const records = readRecords(attempt + "/stage-results.jsonl");
        if (records.problem !== null) {
            fail("the stage result table is unusable: " + records.problem);
        }
        const byId = new Map<string, StageRecord>();
        for (const record of records.records) {
            byId.set(record.stage, record);
        }
        // The membership check is a prefix check over the table that existed
        // before its own result was recorded. The final contract therefore
        // requires the recorded result of both terminal checks, requires each
        // recorded state to agree with the state the caller reports, and
        // requires the membership record to be the last one written.
        const terminal: TerminalCheck[] = [
            { id: "comparison", reported: comparisonState },
            { id: "membership", reported: membershipState },
        ];
        let extra = "";
        let unexpected = 0;
        for (const entry of terminal) {
            if (!manifest.stages.some(stage => stage.id === entry.id)) {
                fail("the frozen manifest declares no " + entry.id + " stage");
            }
            const record = byId.get(entry.id);
            if (record === undefined) {
                extra += "UNEXPECTED " + entry.id + ": no recorded result\n";
                unexpected += 1;
                continue;
            }
            if (record.state !== entry.reported) {
                extra += "UNEXPECTED " + entry.id + ": the recorded state " + record.state
                    + " contradicts the reported " + entry.reported + "\n";
                unexpected += 1;
                continue;
            }
            if (record.state !== "ok") {
                extra += "UNEXPECTED " + entry.id + ": the terminal check did not end ok (" + record.state + ")\n";
                unexpected += 1;
            }
        }
        const last = records.records[records.records.length - 1];
        if (last === undefined || last.stage !== "membership") {
            extra += "UNEXPECTED membership: the terminal membership record is not the last recorded result\n";
            unexpected += 1;
        }
        const previous = JSON.parse(readFileSync(attempt + "/comparison.json", "utf8")) as Partial<StoredComparison>;
        const previousUnexpected = previous.unexpected ?? [];
        unexpected += previousUnexpected.length;
        for (const finding of previousUnexpected) {
            extra += "UNEXPECTED " + finding.stage + ": " + (finding.reason ?? "") + "\n";
        }
        const agreements = previous.agreements ?? 0;
        const observations = previous.observations ?? [];
        const lines = readFileSync(attempt + "/comparison.txt", "utf8");
        // The comparison text keeps its recorded observations and per-stage
        // lines; only its own stale findings and stale verdict are replaced.
        const body = lines.split("\n")
            .filter(line => !line.startsWith("UNEXPECTED ") && !line.startsWith("procedure verdict:")).join("\n");
        const finalText = extra + body
            + "procedure verdict: " + agreements + " agreements, " + observations.length
            + " recorded observations, " + unexpected + " unexpected failure" + (unexpected === 1 ? "" : "s") + "\n";
        writeFileSync(attempt + "/comparison.txt", finalText);
        writeFileSync(attempt + "/comparison.json", JSON.stringify({
            agreements: previous.agreements ?? 0,
            observations: previous.observations ?? [],
            unexpected: previous.unexpected ?? [],
            comparisonStage: comparisonState,
            membershipStage: membershipState,
            unexpectedFailures: unexpected,
        }, null, 2) + "\n");
        process.stdout.write(finalText);
        process.exit(unexpected > 0 ? 1 : 0);
    }

    if (command === "verify") {
        // Bounded controls over the production verdict chain. Every case is
        // written as a real attempt and then measured by the same commands the
        // caller runs: the stage serializer, the membership adapter, the shared
        // checker, the compare entry and the finalize entry. They never touch
        // historical child evidence and they never run a compiler.
        const out = argumentValue(argv, "--out");
        const replay = argumentValue(argv, "--replay");
        const sharedCheck = argumentValue(argv, "--stage-check");
        if (out === null || replay === null || sharedCheck === null) {
            fail("verify needs --out, --replay and --stage-check");
        }
        process.stdout.write(verify(out, replay, sharedCheck) + "\n");
        process.exit(0);
    }

    fail("unknown command: " + command);
}

/** One spawned verdict command: its exit status and its captured streams. */
interface CommandResult {
    exit: number;
    stdout: string;
    stderr: string;
}

/** What one control expects from the production chain. */
interface ControlExpectation {
    name: string;
    /** How the terminal membership record is written: derived, absent, or forced. */
    membershipRecord: "auto" | "absent" | "ok" | "failed";
    /** Writes one more recorded result after the terminal membership record. */
    recordAfterMembership: boolean;
    /** A finding the shared checker must report, or null when it must stay silent. */
    membershipFinding: string | null;
    /** A finding compare must report, or null when it must accept. */
    compareReason: string | null;
    observationsPresent: string[];
    observationsAbsent: string[];
    finalizeAccepts: boolean;
    /** A finding finalize must report, or null when only the exit is asserted. */
    finalizeReason: string | null;
}

/** One control attempt before it is serialized into the attempt layout. */
interface AttemptInput {
    records: StageRecord[];
    reports: Map<string, ProbeReport>;
}

type AttemptMutation = (attempt: AttemptInput) => void;

/** One terminal check of the final contract, with the state the caller reports. */
interface TerminalCheck {
    id: string;
    reported: string;
}

/** Replaces one captured report of a control attempt. */
type ReportChange = (report: ProbeReport) => ProbeReport;

/**
 * Drives the production verdict chain over one complete passing case and over
 * every control derived from it by a single mutation. Each case is written in
 * the attempt layout and then measured by the commands the caller runs: the
 * membership adapter, the shared checker, compare and finalize.
 */
function verify(out: string, replay: string, sharedCheck: string): string {
    const report: string[] = [];
    let defects = 0;
    const script = process.argv[1] ?? "";

    const run = (args: string[]): CommandResult => {
        const child = Bun.spawnSync([process.execPath, script].concat(args), { stdout: "pipe", stderr: "pipe" });
        return { exit: child.exitCode, stdout: child.stdout.toString(), stderr: child.stderr.toString() };
    };
    // Membership authority stays in the shared checker. It runs through its own
    // entry point, exactly as the caller runs it.
    const sharedMembership = (dir: string): CommandResult => {
        const child = Bun.spawnSync(["bash", "-c", 'source "$1" && stage_check "$2" "$3" "$4"', "stage-check",
            sharedCheck, dir + "/status.tsv", dir + "/expected-stages.txt", dir + "/findings.txt"],
            { stdout: "pipe", stderr: "pipe" });
        return { exit: child.exitCode, stdout: child.stdout.toString(), stderr: child.stderr.toString() };
    };

    if (!existsSync(sharedCheck)) {
        defects += 1;
        report.push("FAIL shared-checker (the accepted shared stage checker is missing at " + sharedCheck + ")");
        report.push("verifier verdict: " + defects + " control(s) behaved differently");
        return report.join("\n");
    }

    // --- the complete passing case ------------------------------------------
    const authoredA = linesOf(readFileSync(replay + "/expected/group-a.txt", "utf8"));
    const authoredC = linesOf(readFileSync(replay + "/expected/group-c.txt", "utf8"));
    const textOf = (lines: string[]): string => lines.join("\n") + "\n";
    const replacedLine = "normalizedBinding.null=w:-1";
    const replacedIndex = authoredA.indexOf(replacedLine);
    const rustObserved = authoredA.map((line, index) =>
        index === replacedIndex ? "normalizedBinding.null=w:4294967295" : line);
    const declaredKotlinStderr = "out/flow-contract/verifier/generated-c/kotlin/flow/stable/FlowCases.kt:11:24: error: "
        + "only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver of type 'Cell?'.\n"
        + "        return \"w:\" + b.width\n                       ^\n";
    const manifestSource = readFileSync(replay + "/stages.json", "utf8");

    const baselineReports = (): Map<string, ProbeReport> => new Map([
        ["a-reference", normalReport(textOf(authoredA), "", 0)],
        ["c-reference", normalReport(textOf(authoredC), "", 0)],
        ["a-kotlin-run", normalReport(textOf(authoredA), "", 0)],
        ["a-rust-run", normalReport(textOf(rustObserved), "", 0)],
        ["c-rust-run", normalReport(textOf(authoredC), "", 0)],
        ["c-kotlin-compile", normalReport("", declaredKotlinStderr, 1)],
    ]);

    const baselineRecords = (): StageRecord[] => [
        record("boring-path-check", "ok", "bootstrap/class-paths.txt"),
        record("bootstrap-probe", "ok", "bootstrap/probe-build.status"),
        record("identity-haxe", "ok", "compiler identity"),
        record("identity-kotlinc", "ok", "compiler identity"),
        record("identity-cargo", "ok", "cargo identity"),
        record("identity-rustc", "ok", "rustc identity"),
        record("identity-java", "ok", "runtime identity"),
        record("identity-bun", "ok", "host identity"),
        record("hashes-before", "ok", "hashes-before.txt"),
        record("a-admission", "ok", "source admission of the normalized cases"),
        record("a-reference", "ok", "the reference run"),
        record("a-kotlin-generation", "ok", "generated Kotlin"),
        record("a-kotlin-compile", "ok", "generated Kotlin compiles"),
        record("a-kotlin-run", "ok", "Kotlin result"),
        record("a-rust-generation", "ok", "generated Rust"),
        record("a-rust-build", "ok", "generated Rust builds"),
        record("a-rust-run", "ok", "Rust result"),
        record("c-admission", "ok", "source admission of the stable-local cases"),
        record("c-reference", "ok", "the reference run"),
        record("c-kotlin-generation", "ok", "generated Kotlin"),
        record("c-kotlin-compile", "failed", "the declared observation"),
        record("c-kotlin-run", "not-reached", "not reached; blocked by c-kotlin-compile=failed"),
        record("c-rust-generation", "ok", "generated Rust"),
        record("c-rust-build", "ok", "generated Rust builds"),
        record("c-rust-run", "ok", "Rust result"),
        record("hashes-after", "ok", "the selected input closure is unchanged"),
        record("comparison", "ok", "comparison.txt and comparison.json"),
    ];

    // --- one control: the chain over one mutated copy of that case -----------
    const control = (expectation: ControlExpectation, mutate: AttemptMutation): void => {
        const dir = out + "/cases/" + expectation.name;
        mkdirSync(dir + "/reports", { recursive: true });
        mkdirSync(dir + "/membership", { recursive: true });
        writeFileSync(dir + "/manifest.json", manifestSource);
        const attempt: AttemptInput = { records: baselineRecords(), reports: baselineReports() };
        mutate(attempt);
        writeFileSync(dir + "/stage-results.jsonl", attempt.records.map(stageLine).join("\n") + "\n");
        for (const entry of Array.from(attempt.reports.entries())) {
            writeFileSync(dir + "/reports/" + entry[0] + ".json", JSON.stringify(entry[1]));
        }

        const problems: string[] = [];
        const ids = run(["stage-ids", "--manifest", dir + "/manifest.json",
            "--results", dir + "/stage-results.jsonl", "--out", dir + "/membership", "--exclude", "membership"]);
        if (ids.exit !== 0) {
            problems.push("the membership adapter exited " + ids.exit + ": " + ids.stderr.trim());
        } else {
            const checked = sharedMembership(dir + "/membership");
            const findings = existsSync(dir + "/membership/findings.txt")
                ? readFileSync(dir + "/membership/findings.txt", "utf8").trim() : "";
            if (expectation.membershipFinding === null && (checked.exit !== 0 || findings.length > 0)) {
                problems.push("membership reported " + (findings.length > 0 ? findings : "exit " + checked.exit));
            }
            if (expectation.membershipFinding !== null
                && (checked.exit === 0 || !findings.includes(expectation.membershipFinding))) {
                problems.push("membership did not report " + JSON.stringify(expectation.membershipFinding)
                    + "; it reported " + (findings.length > 0 ? findings : "nothing"));
            }
            const compared = run(["compare", "--attempt", dir, "--replay", replay,
                "--manifest", dir + "/manifest.json", "--exclude", "comparison,membership"]);
            const measured = existsSync(dir + "/comparison.txt") ? readFileSync(dir + "/comparison.txt", "utf8") : "";
            if (expectation.compareReason === null && (compared.exit !== 0 || measured.includes("UNEXPECTED "))) {
                problems.push("compare did not accept (exit " + compared.exit + ")\n" + measured.trim());
            }
            if (expectation.compareReason !== null
                && (compared.exit === 0 || !measured.includes(expectation.compareReason))) {
                problems.push("compare did not report " + JSON.stringify(expectation.compareReason)
                    + "\n" + measured.trim());
            }
            for (const name of expectation.observationsPresent) {
                if (!measured.includes("RECORDED OBSERVATION " + name)) {
                    problems.push("the observation " + name + " is not recorded");
                }
            }
            for (const name of expectation.observationsAbsent) {
                if (measured.includes("RECORDED OBSERVATION " + name)) {
                    problems.push("the observation " + name + " is recorded but must not be");
                }
            }
            // The terminal membership record is written after the table the
            // prefix check examined, exactly as the caller writes it.
            const recordedMembership = expectation.membershipRecord === "auto"
                ? (checked.exit === 0 ? "ok" : "failed")
                : expectation.membershipRecord;
            let table = readFileSync(dir + "/stage-results.jsonl", "utf8");
            if (recordedMembership !== "absent") {
                table += stageLine({ stage: "membership", state: recordedMembership as StageState, detail: findings }) + "\n";
            }
            if (expectation.recordAfterMembership) {
                table += stageLine({ stage: "hashes-after", state: "ok", detail: "a late re-hash" }) + "\n";
            }
            writeFileSync(dir + "/stage-results.jsonl", table);
            const finalized = run(["finalize", "--attempt", dir, "--manifest", dir + "/manifest.json",
                "--comparison-state", compared.exit === 0 ? "ok" : "failed",
                "--membership-state", checked.exit === 0 ? "ok" : "failed"]);
            if (expectation.finalizeAccepts && finalized.exit !== 0) {
                problems.push("finalize rejected\n" + finalized.stdout.trim());
            }
            if (!expectation.finalizeAccepts) {
                if (finalized.exit === 0) {
                    problems.push("finalize accepted");
                } else if (expectation.finalizeReason !== null
                    && !finalized.stdout.includes(expectation.finalizeReason)) {
                    problems.push("finalize did not report " + JSON.stringify(expectation.finalizeReason)
                        + "\n" + finalized.stdout.trim());
                }
            }
        }

        if (problems.length > 0) {
            defects += 1;
            report.push("FAIL " + expectation.name);
            for (const problem of problems) {
                report.push("     " + problem);
            }
            return;
        }
        report.push("pass " + expectation.name);
    };

    const changeReport = (attempt: AttemptInput, stage: string, change: ReportChange): void => {
        const report0 = attempt.reports.get(stage);
        if (report0 === undefined) {
            return;
        }
        attempt.reports.set(stage, change(report0));
    };

    // The one complete passing declared-observation case. Every control below
    // derives from it by changing exactly one condition and keeps every other
    // obligation of the frozen declaration unchanged.
    control({
        name: "complete-declared-observation",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: null,
        observationsPresent: ["kotlin-stable-local-position-proof", "rust-negative-fallback-unsigned"],
        observationsAbsent: [],
        finalizeAccepts: true,
        finalizeReason: null,
    }, () => undefined);

    control({
        name: "declared-stage-without-record",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: "missing stage a-rust-build",
        compareReason: "UNEXPECTED a-rust-build: no recorded result",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        attempt.records = attempt.records.filter(r => r.stage !== "a-rust-build");
    });

    control({
        name: "declared-stage-recorded-twice",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: "duplicate stage a-admission",
        compareReason: "UNEXPECTED a-admission: more than one recorded result",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        attempt.records.push(record("a-admission", "ok", "recorded a second time"));
    });

    control({
        name: "undeclared-recorded-stage",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: "unexpected stage a-rust-run-cargo",
        compareReason: "UNEXPECTED a-rust-run-cargo: a recorded stage the manifest does not declare",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        attempt.records.push(record("a-rust-run-cargo", "ok", "a stage the frozen declaration does not name"));
    });

    control({
        name: "membership-record-absent",
        membershipRecord: "absent",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: null,
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: "UNEXPECTED membership: no recorded result",
    }, () => undefined);

    control({
        name: "membership-record-failed",
        membershipRecord: "failed",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: null,
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: "UNEXPECTED membership: the recorded state failed contradicts the reported ok",
    }, () => undefined);

    control({
        name: "membership-record-not-terminal",
        membershipRecord: "auto",
        recordAfterMembership: true,
        membershipFinding: null,
        compareReason: null,
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: "UNEXPECTED membership: the terminal membership record is not the last recorded result",
    }, () => undefined);

    // The reference run carries the oracle claim. A wrong reference is a
    // conformance failure even while every native output stays correct.
    control({
        name: "reference-output-wrong",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "UNEXPECTED a-reference: line 1 is ",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        changeReport(attempt, "a-reference", report => ({
            ...report,
            stdoutText: textOf(["guardInsideSkippedBranch.flag.true.null=w:7"].concat(authoredA.slice(1))),
        }));
    });

    control({
        name: "rust-line-missing",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "UNEXPECTED a-rust-run: the measured sequence holds 24 lines against 25 authored lines",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        changeReport(attempt, "a-rust-run", report => ({ ...report, stdoutText: textOf(rustObserved.slice(0, 24)) }));
    });

    control({
        name: "rust-line-undocumented-difference",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "UNEXPECTED a-rust-run: line 1 is ",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        changeReport(attempt, "a-rust-run", report => ({
            ...report,
            stdoutText: textOf(["guardInsideSkippedBranch.flag.true.null=w:7"].concat(rustObserved.slice(1))),
        }));
    });

    // Plain agreement is not a nonconformance: when the measured sequence is
    // the authored sequence, no observation is recorded.
    control({
        name: "rust-exact-agreement-is-no-observation",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: null,
        observationsPresent: ["kotlin-stable-local-position-proof"],
        observationsAbsent: ["rust-negative-fallback-unsigned"],
        finalizeAccepts: true,
        finalizeReason: null,
    }, attempt => {
        changeReport(attempt, "a-rust-run", report => ({ ...report, stdoutText: textOf(authoredA) }));
    });

    control({
        name: "unrelated-kotlin-diagnostic",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "does not carry the declared diagnostic kotlin-stable-local-position-proof",
        observationsPresent: [],
        observationsAbsent: ["kotlin-stable-local-position-proof"],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        changeReport(attempt, "c-kotlin-compile", report => ({
            ...report,
            stderrText: "out/flow-contract/verifier/generated-c/kotlin/flow/stable/FlowCases.kt:11:24: error: "
                + "unrelated diagnostic about something else\n",
        }));
    });

    control({
        name: "signaled-kotlin-compiler",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "does not carry the declared diagnostic kotlin-stable-local-position-proof",
        observationsPresent: [],
        observationsAbsent: ["kotlin-stable-local-position-proof"],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        changeReport(attempt, "c-kotlin-compile", report => ({
            ...report,
            outcome: "signaled",
            exitStatus: null,
            signal: "SIGKILL",
        }));
    });

    control({
        name: "producer-state-failed",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "UNEXPECTED a-kotlin-compile: the stage is a producer and its state is failed: ",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        attempt.records = attempt.records.map(r =>
            r.stage === "a-kotlin-compile" ? record("a-kotlin-compile", "failed", "kotlinc reported an error") : r);
    });

    control({
        name: "input-closure-changed",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "UNEXPECTED hashes-after: the stage is a check and its state is changed: ",
        observationsPresent: [],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        attempt.records = attempt.records.map(r =>
            r.stage === "hashes-after" ? record("hashes-after", "changed", "see hashes-after.diff") : r);
    });

    // A failure unrelated to the declared observation still rejects.
    control({
        name: "unrelated-failure-still-rejects",
        membershipRecord: "auto",
        recordAfterMembership: false,
        membershipFinding: null,
        compareReason: "UNEXPECTED c-rust-build: the stage is a producer and its state is failed: ",
        observationsPresent: ["kotlin-stable-local-position-proof"],
        observationsAbsent: [],
        finalizeAccepts: false,
        finalizeReason: null,
    }, attempt => {
        attempt.records = attempt.records.map(r =>
            r.stage === "c-rust-build" ? record("c-rust-build", "failed", "cargo reported an error") : r);
    });

    // --- capture validity: the recorder's own entry, kept separate ----------
    const malformedDir = out + "/cases/capture-malformed-report";
    mkdirSync(malformedDir + "/reports", { recursive: true });
    writeFileSync(malformedDir + "/reports/c-kotlin-compile.json", "{ not json");
    const malformedRead = readJson(malformedDir + "/reports/c-kotlin-compile.json");
    const malformedVerdict = judge(asReport(malformedRead.value), malformedRead.problem, 0);
    if (malformedVerdict.state !== "invalid" || !(malformedVerdict.capture[0] ?? "").includes("not valid JSON")) {
        defects += 1;
        report.push("FAIL capture-malformed-report (state " + malformedVerdict.state + ", capture "
            + JSON.stringify(malformedVerdict.capture) + ")");
    } else {
        report.push("pass capture-malformed-report");
    }

    const incomplete = judge(asReport({
        outcome: "normal-exit",
        exitStatus: 0,
        captureComplete: false,
        evidenceError: null,
        captureError: "the stderr stream write failed",
        stdoutAvailable: true,
        stderrAvailable: false,
    }), null, 0);
    if (incomplete.state !== "invalid"
        || !incomplete.capture.some(reason => reason.includes("captureComplete") || reason.includes("stderr"))) {
        defects += 1;
        report.push("FAIL capture-incomplete-streams (state " + incomplete.state + ", capture "
            + JSON.stringify(incomplete.capture) + ")");
    } else {
        report.push("pass capture-incomplete-streams");
    }

    report.push(defects === 0 ? "verifier verdict: every control behaved as declared"
        : "verifier verdict: " + defects + " control(s) behaved differently");
    return report.join("\n");
}

function record(stage: string, state: StageState, detail: string = ""): StageRecord {
    return { stage, state, detail };
}

/** One captured child that ended normally: the shape the probe reports. */
function normalReport(stdoutText: string, stderrText: string, exitStatus: number): ProbeReport {
    return {
        outcome: "normal-exit",
        exitStatus,
        signal: null,
        captureComplete: true,
        evidenceError: null,
        captureError: null,
        stdoutAvailable: true,
        stderrAvailable: true,
        stdoutText,
        stderrText,
        childDirectory: null,
    };
}

main();
