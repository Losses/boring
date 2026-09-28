import {readFile, writeFile} from "node:fs/promises";
import path from "node:path";

type Coordinate = {
	line: number;
	column: number;
};

type SourceRange = {
	occurrenceId: string;
	file: string;
	start: number;
	end: number;
};

type SidecarSpan = {
	status: "mapped" | "unmapped";
	generated: {
		file: string;
		start: Coordinate;
		end: Coordinate;
	};
	source: SourceRange | null;
	reason: string | null;
};

type Sidecar = {
	output: string;
	spans: SidecarSpan[];
};

function requireCondition(condition: boolean, message: string): asserts condition {
	if (!condition) {
		throw new Error(message);
	}
}

async function mutateMapped(stage: string, sidecarPath: string, sidecar: Sidecar, mode: string): Promise<void> {
	const calls = sidecar.spans.filter((span) => span.status === "mapped"
		&& span.source?.file.endsWith("DiagnosticSubject.hx") === true
		&& span.source.occurrenceId.startsWith("DiagnosticSubject.DiagnosticSubject.run#"))
		.sort((left, right) => (left.source?.start ?? 0) - (right.source?.start ?? 0));
	requireCondition(calls.length === 2, "expected two mapped call occurrences in the diagnostic fixture");
	const selected = calls[1];
	requireCondition(selected.source !== null && selected.generated.start.line === selected.generated.end.line,
		"second call must have one mapped generated line and an original occurrence");
	const source = await readFile(selected.source.file, "utf8");
	const generatedPath = path.join(stage, sidecar.output);
	const lines = (await readFile(generatedPath, "utf8")).split("\n");
	lines[selected.generated.start.line - 1] = "    DiagnosticSubject.emit(0);";
	await writeFile(generatedPath, lines.join("\n"));
	const sourceLine = source.slice(0, selected.source.start).split("\n").length;
	await writeFile(`${generatedPath}.selected.json`, JSON.stringify({
		occurrenceId: selected.source.occurrenceId,
		sourceLine,
		generated: selected.generated
	}, null, "\t") + "\n");
	if (mode === "bad-generated-file") selected.generated.file = "../outside.ts";
	if (mode === "bad-generated-range") selected.generated.end.line = 100000;
	if (mode === "bad-source-range") selected.source.end = source.length + 100;
	if (mode === "bad-source-path") selected.source.file = "../../../../../../etc/passwd";
	if (mode === "bad-source-symlink") {
		const link = process.env.TS_DIAGNOSTIC_ESCAPE_SOURCE;
		requireCondition(link != null, "symlink control requires an existing source link");
		selected.source.file = link;
	}
	if (mode === "bad-source-order") selected.source.end = selected.source.start;
	if (mode === "malformed-sidecar") {
		await writeFile(sidecarPath, "{bad json\n");
	} else if (mode !== "mapped") {
		await writeFile(sidecarPath, JSON.stringify(sidecar, null, "\t") + "\n");
	}
}

async function mutateHelper(stage: string, sidecar: Sidecar): Promise<void> {
	const helper = sidecar.spans.find((span) => span.status === "unmapped" && span.reason === "generated-helper");
	requireCondition(helper !== undefined, "expected a generated-helper sidecar range");
	const generatedPath = path.join(stage, sidecar.output);
	const lines = (await readFile(generatedPath, "utf8")).split("\n");
	lines[helper.generated.start.line - 1] += " const packageHelperTypeError: string = 1;";
	await writeFile(generatedPath, lines.join("\n"));
}

const [stageArg, sidecarArg, mode] = Bun.argv.slice(2);
requireCondition(stageArg != null && sidecarArg != null && mode != null, "stage, sidecar, and mutation mode are required");
const sidecar = JSON.parse(await readFile(sidecarArg, "utf8")) as Sidecar;
if (mode === "mapped" || mode.startsWith("bad-") || mode === "malformed-sidecar") {
	await mutateMapped(stageArg, sidecarArg, sidecar, mode);
} else if (mode === "helper") {
	await mutateHelper(stageArg, sidecar);
} else {
	throw new Error(`unsupported mutation mode: ${mode}`);
}
