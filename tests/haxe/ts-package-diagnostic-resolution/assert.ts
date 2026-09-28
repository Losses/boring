import {readFile} from "node:fs/promises";

type Selected = {
	occurrenceId: string;
	sourceLine: number;
	generated: {
		start: {line: number; column: number};
		end: {line: number; column: number};
	};
};

function requireCondition(condition: boolean, message: string): asserts condition {
	if (!condition) {
		throw new Error(message);
	}
}

const [mode, stdoutPath, stderrPath, selectedPath] = Bun.argv.slice(2);
requireCondition(mode != null && stdoutPath != null && stderrPath != null, "mode and captured Haxe streams are required");
const stdout = await readFile(stdoutPath, "utf8");
const stderr = await readFile(stderrPath, "utf8");
if (mode === "mapped" || mode === "mapped-no-stress") {
	requireCondition(selectedPath != null, "mapped mode requires selected occurrence metadata");
	const selected = JSON.parse(await readFile(selectedPath, "utf8")) as Selected;
	requireCondition(stderr.includes("package-tsc failed with exit code 2:"), "child tsc exit status must be retained");
	requireCondition(stderr.includes("source resolution: Mapped to tests/haxe/ts-package-diagnostic-resolution/DiagnosticSubject.hx:"),
		"diagnostic must resolve to the original Haxe file span");
	requireCondition(stderr.includes(`occurrence ${selected.occurrenceId}`), "diagnostic must name the second source occurrence");
	requireCondition(stderr.includes(`DiagnosticSubject.hx:${selected.sourceLine}:`), "Haxe fatal position must use the selected source line");
	const location = /DiagnosticSubject\.ts\((\d+),(\d+)\): error TS2345:/.exec(stdout);
	requireCondition(location !== null, "original tsc TS2345 location and diagnostic must be preserved");
	const generatedLine = Number(location[1]);
	const generatedColumn = Number(location[2]);
	requireCondition(stdout.includes(".package-npm-stage/DiagnosticSubject.ts("), "raw child location must identify the npm stage copy");
	requireCondition(generatedLine === selected.generated.start.line
		&& generatedColumn >= selected.generated.start.column
		&& generatedColumn < selected.generated.end.column,
		"tsc generated coordinate must fall inside the selected original mapped range");
	requireCondition(stdout.includes("Argument of type 'number' is not assignable to parameter of type 'string'."),
		"raw tsc diagnostic text must remain present");
	if (mode === "mapped") {
		requireCondition(stdout.startsWith("O".repeat(131072) + "\n"), "large child stdout must be forwarded without alteration");
		requireCondition(stderr.startsWith("E".repeat(131072) + "\n"), "large child stderr must be forwarded without alteration");
	}
} else if (mode === "helper") {
	requireCondition(stderr.includes("package-tsc failed with exit code 2:"), "helper child exit status must be retained");
	requireCondition(stderr.includes("source resolution: Unmapped (generated-helper)"), "generated helper errors must remain explicitly Unmapped");
	requireCondition(/DiagnosticHelper\.ts\(\d+,\d+\): error TS2322:/.test(stdout), "raw helper diagnostic location must remain present");
} else if (mode === "haxe") {
	requireCondition(stderr.includes("Unknown identifier : notDefined"), "invalid Haxe input must retain its Haxe typing error");
	requireCondition(!stderr.includes("package-tsc failed"), "Haxe typing rejection must not be described as a child compiler error");
} else {
	throw new Error(`unsupported assertion mode: ${mode}`);
}
