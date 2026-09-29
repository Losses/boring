// Runtime-byte check for the generated TemplateShape module. The expected
// values are the Haxe source bytes; no snapshot of generated output is
// consulted.
import { pathToFileURL } from "node:url";

const expected: Record<string, string> = {
    lf: "l1\nl2",
    cr: "c1\rc2",
    crlf: "w1\r\nw2",
    backtick: "t1`t2",
    interpolation: "i1${value}i2",
    backslash: "b1\\b2"
};

const modulePath = process.argv[2];
if (modulePath == null) {
    console.error("usage: bun check.ts <generated TemplateShape.ts>");
    process.exit(2);
}
type ShapeQuery = () => string;

type TemplateShapeModule = {
    TemplateShape: Record<string, ShapeQuery>;
};

const loaded = await import(pathToFileURL(modulePath).href);
const generated = loaded as Partial<TemplateShapeModule>;
const shape = generated.TemplateShape;
if (shape == null) {
    console.error("generated module exposes no TemplateShape export");
    process.exit(2);
}
let failures = 0;
for (const name of Object.keys(expected)) {
    const actual = shape[name]();
    if (actual !== expected[name]) {
        failures += 1;
        console.error(name + " mismatch: expected " + JSON.stringify(expected[name])
            + ", actual " + JSON.stringify(actual));
    }
}
if (failures > 0) {
    console.error("TEMPLATE ESCAPE FAIL: " + failures + " mismatch(es)");
    process.exit(1);
}
console.log("TEMPLATE ESCAPE PASS");