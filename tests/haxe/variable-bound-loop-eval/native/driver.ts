// Native invocation driver for the variable-bound-loop-eval fixture (TypeScript).
//
// The runner copies this file into the generated tree root, so the relative
// import reaches <tree>/vble/Probe.ts. The driver only observes: it calls the
// three generated probe functions once each and prints the three returned
// bound-read counts. The generated main() calls the fixture shadow of
// haxe.Log (a no-op), so this driver is the only printer of the observation
// line. It takes no verdict; the runner compares the printed observation with
// the authored expectation.
//
// The pinned toolchain ships no @types/node, so the little of the Node surface
// this driver uses is declared here instead of pulled from the network. The
// generated modules are compiled unmodified; only this authored driver carries
// the declaration.
declare const process: {
	argv: string[];
	stdout: { write(text: string): void };
	stderr: { write(text: string): void };
	exit(code: number): void };

import { Probe } from "./vble/Probe.ts";

const local: number = Probe.localBound();
const length: number = Probe.growingLength();
const control: number = Probe.doubleControl();
process.stdout.write(`local=${local} length=${length} control=${control}\n`);
