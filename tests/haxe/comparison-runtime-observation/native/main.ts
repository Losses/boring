// Native invocation harness for the TypeScript generated tree of the
// comparison observation fixture. The runner copies this file into its run
// directory beside the generated tree, so the relative import reaches
// <run>/ts-gen/comparison/ComparisonObserve.ts. The harness prints the text
// one generated observation function returns; it holds no ordering decision
// and re-implements no comparator. The case name is the first argument after
// the interpreter and this file, which is process.argv[2] under bun.
import { ComparisonObserve } from "../ts-gen/comparison/ComparisonObserve.ts";

type Observation = () => string;
type ObservationTable = Record<string, Observation>;

const observations: ObservationTable = {
	"int-ordinary": () => ComparisonObserve.intOrdinary(),
	"int-extremes": () => ComparisonObserve.intExtremes(),
	"array-order": () => ComparisonObserve.arrayOrder(),
	"nullable-order": () => ComparisonObserve.nullableOrder(),
	"string-order": () => ComparisonObserve.stringOrder(),
};

const requested: string | undefined = process.argv[2];
const observation: Observation | undefined = requested === undefined ? undefined : observations[requested];

if (requested === undefined || observation === undefined) {
	process.stderr.write(`comparison harness: unknown case ${String(requested)}\n`);
	process.exit(2);
}

process.stdout.write(`${observation()}\n`);
