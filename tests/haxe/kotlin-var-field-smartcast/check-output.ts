// The focused check of the var-property smart-cast probe.
//
// Kotlin does not smart-cast a mutable property, so a read through a nullable
// `var` must keep its force extraction even when a null guard proves the value
// present; a `final` (val) property may smart-cast. Commit 8214566d ("fix
// (kotlin): keep force extraction on var-property null-narrowing") added that
// distinction on the ci/collected-suite-failure-attribution lineage (it is not
// on the arch/agent-guided-governance base), and no test in either tree pinned
// it, which is how a merge silently dropped it and left the emitted Kotlin
// failing kotlinc.
// (VarFieldSmartCast)
//
// Run from the worktree root after kotlin-gen.hxml:
//   bun tests/haxe/kotlin-var-field-smartcast/check-output.ts
import { readFileSync } from "node:fs";

const root = "out/kotlin-var-field-smartcast/gen/varfieldsmartcast";
const ops = readFileSync(`${root}/VarFieldSmartCastOps.kt`, "utf8");

/** The body of one `fun name(...)` declaration, up to its closing brace. */
function functionBody(name: string): string {
  const start = ops.indexOf(`fun ${name}(`);
  if (start < 0) throw new Error(`no emitted function ${name}`);
  const open = ops.indexOf("{", start);
  let depth = 0;
  for (let index = open; index < ops.length; index++) {
    if (ops[index] === "{") depth++;
    if (ops[index] === "}") {
      depth--;
      if (depth === 0) return ops.slice(open, index + 1);
    }
  }
  throw new Error(`unterminated body of ${name}`);
}

const failures: Array<string> = [];
function check(what: string, ok: boolean): void {
  if (!ok) failures.push(what);
}

const varBody = functionBody("readThroughVar");
const valBody = functionBody("readThroughVal");

// A read through a mutable property keeps its extraction.
check(
  "readThroughVar must extract a mutable property (expected `holder.value!!.`)",
  /holder\.value!!\./.test(varBody),
);
// The val-side control must NOT be extracted: the distinction is the point.
check(
  "readThroughVal must smart-cast a final property (expected bare `holder.value.`)",
  /holder\.value\./.test(valBody) && !/holder\.value!!\./.test(valBody),
);
// Neither may degrade to a safe call.
check("readThroughVar must not emit a safe call", !/\?\./.test(varBody));
check("readThroughVal must not emit a safe call", !/\?\./.test(valBody));

if (failures.length > 0) {
  for (const failure of failures) console.error(`FAIL: ${failure}`);
  console.error(`\n--- emitted VarFieldSmartCastOps.kt ---\n${ops}`);
  console.error(`kotlin var-field smart-cast: ${failures.length} failure(s)`);
  process.exit(1);
}
console.log("kotlin var-field smart-cast: var keeps `!!`, val smart-casts (2 assertions)");
