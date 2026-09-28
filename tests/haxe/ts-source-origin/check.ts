import { readFile, writeFile } from "node:fs/promises";

type Coordinate = {
	line: number;
	column: number;
};

type GeneratedRange = {
	file: string;
	start: Coordinate;
	end: Coordinate;
};

type SourceRange = {
	occurrenceId: string;
	file: string;
	start: number;
	end: number;
};

type SidecarSpan = {
	status: "mapped" | "unmapped";
	generated: GeneratedRange;
	source: SourceRange | null;
	reason: string | null;
};

type Sidecar = {
	version: number;
	coordinateUnit: string;
	defaultResolution: "Unmapped";
	output: string;
	spans: SidecarSpan[];
};

function requireCondition(condition: boolean, message: string): void {
	if (!condition) {
		throw new Error(message);
	}
}

async function loadSidecar(path: string): Promise<Sidecar> {
	return JSON.parse(await readFile(path, "utf8")) as Sidecar;
}

function sourceLine(sourceText: string, offset: number): number {
	return sourceText.slice(0, offset).split("\n").length;
}

function lookup(sidecar: Sidecar, line: number, column: number): SidecarSpan | null {
	return sidecar.spans.find((span) => positionAtOrBefore(span.generated.start, { line, column })
		&& positionBefore({ line, column }, span.generated.end)) ?? null;
}

function resolveStatus(sidecar: Sidecar, line: number, column: number): "Mapped" | "Unmapped" {
	const span = lookup(sidecar, line, column);
	if (span !== null) {
		return span.status === "mapped" ? "Mapped" : "Unmapped";
	}
	return sidecar.defaultResolution;
}

function positionAtOrBefore(left: Coordinate, right: Coordinate): boolean {
	return left.line < right.line || (left.line === right.line && left.column <= right.column);
}

function positionBefore(left: Coordinate, right: Coordinate): boolean {
	return left.line < right.line || (left.line === right.line && left.column < right.column);
}

async function check(generatedPath: string, sidecarPath: string): Promise<void> {
	const generated = await readFile(generatedPath, "utf8");
	const sidecar = await loadSidecar(sidecarPath);
	const sourceText = await readFile("tests/haxe/ts-source-origin/OriginSubject.hx", "utf8");
	const mapped = sidecar.spans.filter((span) => span.status === "mapped");
	const subjectCalls = mapped.filter((span) => span.source?.occurrenceId.startsWith("OriginSubject.OriginSubject.run#") === true);
	requireCondition(sidecar.version === 1, "unexpected sidecar version");
	requireCondition(sidecar.coordinateUnit === "utf16-code-units", "coordinate unit must match TypeScript columns");
	requireCondition(sidecar.defaultResolution === "Unmapped", "coordinates outside a mapped span must resolve as Unmapped");
	requireCondition(subjectCalls.length === 2, "expected exactly two mapped calls in OriginSubject.run");
	requireCondition(subjectCalls[0].source !== null && subjectCalls[1].source !== null, "mapped source range is missing");
	requireCondition(subjectCalls[0].source?.occurrenceId !== subjectCalls[1].source?.occurrenceId, "same-text source calls need distinct occurrence IDs");
	requireCondition(subjectCalls[0].source?.start !== subjectCalls[1].source?.start, "same-text source calls need distinct source positions");
	requireCondition(sourceLine(sourceText, subjectCalls[0].source?.start ?? -1) === 10, "first source occurrence must be line 10");
	requireCondition(sourceLine(sourceText, subjectCalls[1].source?.start ?? -1) === 11, "second source occurrence must be line 11");
	requireCondition(subjectCalls[0].generated.start.line === 13 && subjectCalls[1].generated.start.line === 14, "final module offsets must include header, import, and earlier declaration fragments");
	requireCondition(subjectCalls.every((span) => span.generated.start.column === 1 && span.generated.end.column === 29), "mapped ranges must use UTF-16 columns for the astral string literal");
	const generatedLines = generated.split("\n");
	requireCondition(generatedLines[12] === '    OriginSubject.emit("😀");' && generatedLines[13] === generatedLines[12], "generated call statements must remain text-identical");
	const firstLookup = lookup(sidecar, 13, 5);
	const secondLookup = lookup(sidecar, 14, 5);
	requireCondition(firstLookup?.source?.occurrenceId === subjectCalls[0].source?.occurrenceId, "first exact generated range lookup failed");
	requireCondition(secondLookup?.source?.occurrenceId === subjectCalls[1].source?.occurrenceId, "second exact generated range lookup failed");
	requireCondition(lookup(sidecar, 14, 29) === null, "end-exclusive range boundary must not resolve as mapped");
	requireCondition(sidecar.spans.some((span) => span.status === "unmapped" && span.generated.start.line === 1 && span.reason === "generated-header"), "generated header must be explicitly Unmapped");
	requireCondition(lookup(sidecar, 1, 1)?.status === "unmapped", "helper/header coordinate must resolve explicitly as Unmapped");
	requireCondition(sidecar.spans.some((span) => span.status === "unmapped" && span.reason === "generated-imports"), "generated import must be explicitly Unmapped");
	requireCondition(lookup(sidecar, 3, 5)?.reason === "generated-imports", "import coordinate must resolve explicitly as Unmapped");
	const sameModuleRuns = mapped.filter((span) => span.source?.occurrenceId.includes(".run#") === true);
	const occurrenceIds = sameModuleRuns.map((span) => span.source?.occurrenceId ?? "");
	requireCondition(new Set(occurrenceIds).size === occurrenceIds.length, "same-named methods in distinct classes collided");
}

async function writeSwapped(sourcePath: string, destinationPath: string): Promise<void> {
	const sidecar = await loadSidecar(sourcePath);
	const calls = sidecar.spans.filter((span) => span.status === "mapped"
		&& span.source?.occurrenceId.startsWith("OriginSubject.OriginSubject.run#") === true);
	requireCondition(calls.length === 2 && calls[0].source !== null && calls[1].source !== null, "cannot prepare swap control");
	const first = calls[0].source;
	const second = calls[1].source;
	calls[0].source = second;
	calls[1].source = first;
	await writeFile(destinationPath, `${JSON.stringify(sidecar, null, "\t")}\n`);
}

const [mode, generatedPath, sidecarPath, swappedPath] = Bun.argv.slice(2);
if (mode === "swap") {
	if (generatedPath == null || sidecarPath == null) {
		throw new Error("swap mode requires input and output sidecar paths");
	}
	await writeSwapped(generatedPath, sidecarPath);
} else if (mode === "helper") {
	if (generatedPath == null || sidecarPath == null) {
		throw new Error("helper mode requires generated source and sidecar paths");
	}
	const generated = (await readFile(generatedPath, "utf8")).split("\n");
	const sidecar = await loadSidecar(sidecarPath);
	const helper = sidecar.spans.find((span) => span.status === "unmapped" && span.reason === "generated-helper");
	requireCondition(generated[2]?.includes("const fsExists") === true, "fixture must render the production std.Fs helper");
	requireCondition(helper?.generated.start.line === 3 && helper.generated.end.line === 4, "production helper must have an explicit generated range");
	requireCondition(lookup(sidecar, 3, 5)?.reason === "generated-helper", "helper range lookup must resolve explicitly as Unmapped");
	requireCondition(generated[7]?.trim() === "value = value + 1;", "fixture must retain the unsupported assignment statement");
	requireCondition(lookup(sidecar, 8, 5) === null, "unsupported body position must be outside the sparse mapped spans");
	requireCondition(resolveStatus(sidecar, 8, 5) === "Unmapped", "a gap must resolve through defaultResolution");
	requireCondition(resolveStatus(sidecar, 3, 5) === "Unmapped", "explicit helper range must resolve as Unmapped");
	requireCondition(sidecar.defaultResolution === "Unmapped", "sparse gaps must default to Unmapped");
} else {
	if (generatedPath == null || sidecarPath == null) {
		throw new Error("check mode requires generated source and sidecar paths");
	}
	await check(generatedPath, sidecarPath);
}
