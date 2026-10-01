// TypeScript native harness. The runner copies this file into the
// generated tree root as alias-transfer-run.js, bundles it with bun, and
// runs the bundle. It calls the five authored shape functions and prints
// the labeled lines every other harness prints.
import { ContainerAliasOracle } from "./atb/ContainerAliasOracle.js";

const lines = [
	"field=" + ContainerAliasOracle.field(),
	"fieldNull=" + ContainerAliasOracle.fieldNull(),
	"fieldRebind=" + ContainerAliasOracle.fieldRebind(),
	"relay=" + ContainerAliasOracle.relay(),
	"relayFresh=" + ContainerAliasOracle.relayFresh()
];
for (const line of lines) {
	console.log(line);
}
