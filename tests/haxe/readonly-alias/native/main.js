// TypeScript native harness. The runner copies this file into the
// generated tree root as readonly-alias-run.js, bundles it with bun, and
// runs the bundle. It calls the five authored shape functions and prints
// the labeled lines every other harness prints.
import { ReadOnlyAliasOracle } from "./roalias/ReadOnlyAliasOracle.js";

const lines = [
	"alias=" + ReadOnlyAliasOracle.alias(),
	"passed=" + ReadOnlyAliasOracle.passed(),
	"escaped=" + ReadOnlyAliasOracle.escaped(),
	"rebind=" + ReadOnlyAliasOracle.rebind(),
	"boundary=" + ReadOnlyAliasOracle.boundary()
];
for (const line of lines) {
	console.log(line);
}
