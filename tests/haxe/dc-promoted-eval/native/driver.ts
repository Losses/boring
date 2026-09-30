// Native invocation driver for the dc-promoted-eval fixture (TypeScript).
//
// The runner copies this file into the generated tree root, so the relative
// imports reach <tree>/dcpe/EvalProbe.ts and <tree>/dcpe/DoubleEvalControl.ts.
// The driver only observes: it resets the probe counter, calls the probe once,
// and prints the counter. It takes no verdict; the runner compares the printed
// observation with the authored expectation.
//
// The pinned devShell ships no `@types/node`, so the little of the Node surface
// this driver uses is declared here instead of pulled from the network. The
// generated modules are compiled unmodified; only this authored driver carries
// the declaration.
declare const process: {
	argv: string[];
	stdout: { write(text: string): void };
	stderr: { write(text: string): void };
	exit(code: number): void;
};

import { EvalProbe } from "./dcpe/EvalProbe.ts";
import { DoubleEvalControl } from "./dcpe/DoubleEvalControl.ts";

const requested: string | undefined = process.argv[2];

if (requested === "promoted") {
	EvalProbe.reset();
	const acc: number = EvalProbe.promotedOnce();
	process.stdout.write(`case=promoted acc=${acc} callCount=${EvalProbe.callCount}\n`);
} else if (requested === "double") {
	DoubleEvalControl.reset();
	const acc: number = DoubleEvalControl.doubleOnce();
	process.stdout.write(`case=double acc=${acc} callCount=${DoubleEvalControl.callCount}\n`);
} else {
	process.stderr.write(`dc-promoted-eval ts driver: unknown case ${String(requested)}\n`);
	process.exit(2);
}
