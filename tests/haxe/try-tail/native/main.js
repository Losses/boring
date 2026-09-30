// TypeScript native harness. The runner copies this file into the generated
// tree root as try-tail-run.js and runs it with bun.
import { TryTailOracle } from "./trytail/TryTailOracle.js";
const shapes = [
	["p1-init", "p1Init"], ["p1-ret", "p1Ret"], ["p1-handler", "p1Handler"],
	["p2-init", "p2Init"], ["p2-ret", "p2Ret"], ["p2-handler", "p2Handler"],
	["p3-init", "p3Init"], ["p3-ret", "p3Ret"], ["p3-handler", "p3Handler"],
	["p4-init", "p4Init"], ["p4-ret", "p4Ret"], ["p4-handler", "p4Handler"]
];
for (const [label, name] of shapes) {
	console.log(label + "=" + TryTailOracle[name]());
}
