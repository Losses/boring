// Native invocation harness for the TypeScript generated tree of the signed
// key composition fixture. The runner copies this file into its run directory
// beside the generated tree, so the relative import reaches
// <run>/ts-gen/composition/KeyCompositionObserve.ts. The harness prints the
// text one generated observation function returns; it holds no ordering
// decision and re-implements no comparator. The case name is the first
// argument after the interpreter and this file, which is process.argv[2]
// under bun.
import { KeyCompositionObserve } from "../ts-gen/composition/KeyCompositionObserve.ts";

type Observation = () => string;
type ObservationTable = Record<string, Observation>;

const observations: ObservationTable = {
	"direct-int": () => KeyCompositionObserve.directInt(),
	"direct-int-extremes": () => KeyCompositionObserve.directIntExtremes(),
	"typedef-int": () => KeyCompositionObserve.typedefInt(),
	"typedef-int-extremes": () => KeyCompositionObserve.typedefIntExtremes(),
	"composite-nullable": () => KeyCompositionObserve.compositeNullable(),
	"composite-extremes": () => KeyCompositionObserve.compositeExtremes(),
};

const requested: string | undefined = process.argv[2];
const observation: Observation | undefined = requested === undefined ? undefined : observations[requested];

if (requested === undefined || observation === undefined) {
	process.stderr.write(`signed-key-composition harness: unknown case ${String(requested)}\n`);
	process.exit(2);
}

process.stdout.write(`${observation()}\n`);
