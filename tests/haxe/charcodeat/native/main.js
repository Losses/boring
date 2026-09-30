// TypeScript native harness. The runner copies this file into the
// generated tree root as charcodeat-run.js, bundles it with bun, and
// runs the bundle. It calls the six authored shape functions and
// prints the labeled lines every other harness prints; a nullable code
// unit that is null or undefined is rendered as the token "null"
// (the JS oracle renders the same miss as the token "null" through
// null-collapse, so the compare stage is display-neutral).
import { CharCodeAtOracle } from "./charcodeat/CharCodeAtOracle.js";

const text = (v) => (v === null || v === undefined ? "null" : String(v));

const lines = [
	"subRev=" + CharCodeAtOracle.subRev(),
	"subHigh=" + CharCodeAtOracle.subHigh(),
	"subNeg=" + CharCodeAtOracle.subNeg(),
	"codeNull=" + text(CharCodeAtOracle.codeNull()),
	"codeNeg=" + text(CharCodeAtOracle.codeNeg()),
	"codeInt=" + text(CharCodeAtOracle.codeInt())
];
for (const line of lines) {
	console.log(line);
}
