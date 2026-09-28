import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const root = "out/kotlin-local-presence-consumer/kotlin-gen/kotlinlocalpresence";
const ops = readFileSync(`${root}/LocalPresenceOps.kt`, "utf8");
const enumOps = readFileSync(`${root}/LocalPresenceEnumOps.kt`, "utf8");
const facts = readFileSync("out/kotlin-local-presence-consumer/source-facts.tsv", "utf8");
const preparedFacts = readFileSync("out/kotlin-local-presence-consumer/prepared-root-facts.tsv", "utf8");
const consumerFacts = readFileSync("out/kotlin-local-presence-consumer/production-use-facts.tsv", "utf8");

function blockAfter(source: string, startAt: number): string {
  const open = source.indexOf("{", startAt);
  if (open < 0) throw new Error("expected Kotlin block opener");
  let depth = 0;
  for (let index = open; index < source.length; index++) {
    if (source[index] === "{") depth++;
    if (source[index] === "}") {
      depth--;
      if (depth === 0) return source.slice(startAt, index + 1);
    }
  }
  throw new Error("unterminated Kotlin block");
}

function functionBlock(source: string, name: string): string {
  const start = source.indexOf(`fun ${name}(`);
  if (start < 0) throw new Error(`missing Kotlin function ${name}`);
  return blockAfter(source, start);
}

function initBlock(source: string): string {
  const start = source.indexOf("init {");
  if (start < 0) throw new Error("missing constructor init block");
  return blockAfter(source, start);
}

const present = functionBlock(ops, "presentLocal");
const absent = functionBlock(ops, "absentLocal");
const unknownOptional = functionBlock(ops, "unknownOptional");
const unknownRequired = functionBlock(ops, "unknownRequired");
const construction = functionBlock(ops, "producedConstruction");
const call = functionBlock(ops, "producedCall");
const field = functionBlock(ops, "producedField");
const nullableTextReader = blockAfter(ops, ops.indexOf("interface NullableTextReader"));
const classOps = ops.slice(ops.indexOf("class LocalPresenceOps"));
const read = functionBlock(classOps, "read");
const override = functionBlock(ops, "render");
const ordinary = functionBlock(ops, "ordinaryReturn");
const nested = functionBlock(ops, "nestedLiteral");
const nestedNames = functionBlock(ops, "nestedNameRestore");
const defaulted = functionBlock(ops, "defaultedNullable");
const unprovenString = functionBlock(ops, "unprovenNullableUppercase");
const fusedLoop = functionBlock(ops, "fusionLoopTrailing");
const staticEntry = functionBlock(ops, "staticEntry");
const constructor = initBlock(ops);
const firstPayload = functionBlock(enumOps, "firstPayloadMember");
const secondPayload = functionBlock(enumOps, "secondPayloadMember");

const checks: Array<[string, boolean]> = [
  ["present local direct access", present.includes("if ((local != null)) {\n                return local.read(\"present\")")],
  ["absent nullable storage", absent.includes("val local: String? = null") && absent.includes("return local")],
  ["unknown optional storage", unknownOptional.includes("value: LocalPresenceOps?): LocalPresenceOps?") && unknownOptional.includes("return local")],
  ["unknown required storage", unknownRequired.includes("value: LocalPresenceOps?): LocalPresenceOps") && unknownRequired.includes("val local = value!!")],
  ["nonlocal construction result", construction.includes("val local = LocalPresenceOps(null)") && construction.includes("return local")],
  ["nonlocal call result", call.includes("val local = value.uppercase()") && call.includes("return local")],
  ["nonlocal field result", field.includes("val local = value.label") && field.includes("return local")],
  ["interface method declared return", nullableTextReader.includes("fun read(value: String?): String")],
  ["interface override operation and return", override.includes("override fun render(value: LocalPresenceOps?): String") && override.includes("return value?.read(\"override\")!!")],
  ["ordinary widened return operation and type", ordinary.includes("fun ordinaryReturn(value: LocalPresenceOps?): String?") && ordinary.includes("return value?.read(\"ordinary\")")],
  ["nested literal entry", nested.includes("fun nestedLiteral(value: LocalPresenceOps?): String")],
  ["static function entry", staticEntry.includes("fun staticEntry(value: LocalPresenceOps?): String") && staticEntry.includes("return value.read(\"static\")")],
  ["actual Haxe constructor context", ops.includes("class LocalPresenceOps(value: LocalPresenceOps?)") && constructor.includes("if ((value != null))") && constructor.includes("value.read(\"constructor\")")],
  ["payload member one uses its narrowed local", firstPayload.includes("is LocalPresencePayloadChoice.Text -> choice.value")],
  ["payload member two uses its narrowed local", secondPayload.includes("is LocalPresencePayloadChoice.Text -> \"again-\" + choice.value")],
  ["nested guarded local direct proof", nested.includes("return value.read(\"nested\")")],
  ["prepared nested occurrence reaches production query", /nestedLiteral\tNestedBody\tvalue\tAvailable\tPresent\t1/.test(preparedFacts) && /nestedLiteral\tNestedBody\tvalue\tAvailable\tPresent\t1\ttrue/.test(consumerFacts)],
  ["prepared fusion loop trailing occurrence", /fusionLoopTrailing\tFunctionBody\tlocal\tAvailable\tPresent\t3/.test(preparedFacts) && fusedLoop.includes("val result = local")],
  ["defaulted nullable source and nonnull target entry", /defaultedNullable\tFunctionBody\tvalue\tAvailable\tUnknown\t0/.test(preparedFacts) && /defaultedNullable\tTargetEntry\tvalue\ttrue/.test(consumerFacts) && defaulted.includes('value: String = "ready"') && defaulted.includes("return value.uppercase()")],
  ["unproven nullable String keeps safe access", /unprovenNullableUppercase\tFunctionBody\tvalue\tAvailable\tUnknown\t0/.test(preparedFacts) && /unprovenNullableUppercase\tTargetEntry\tvalue\tfalse/.test(consumerFacts) && unprovenString.includes("value: String?): String?") && unprovenString.includes("return value?.uppercase()")],
  ["outer local name after nested literal", nestedNames.includes('val after = "inner"') && nestedNames.includes('val after = "outer"') && nestedNames.includes("return callback() + after")],
  ["nested read belongs to its own occurrence", /nestedLiteral#nested\tvalue\tLocalUse\(\d+\)\tAvailable\tTransferred\tPresent\t\d+/.test(facts) && /nestedLiteral#outer\tvalue\tLocalUse\(\d+\)\tNoOccurrence\tConservative\tUnknown\tnone/.test(facts)],
  ["fusion loop trailing read retains occurrence", /fusionLoopTrailing\tlocal\tLocalUse\(\d+\)\tAvailable\tTransferred\tPresent\t\d+/.test(facts) && fusedLoop.includes("val result = local")],
  ["source analysis observes local Present", /presentLocal\tlocal\tLocalUse\(\d+\)\tAvailable\tTransferred\tPresent\t\d+/.test(facts)],
  ["source analysis observes local Absent", /absentLocal\tlocal\tLocalUse\(\d+\)\tAvailable\tTransferred\tAbsent\t\d+/.test(facts)],
  ["source analysis observes local Unknown", /unknownOptional\tlocal\tLocalUse\(\d+\)\tAvailable\tTransferred\tUnknown\t\d+/.test(facts) && /unknownRequired\tlocal\tLocalUse\(\d+\)\tAvailable\tTransferred\tUnknown\t\d+/.test(facts)],
  ["source analysis retains local NoOccurrence", /unavailableLocal\tlocal\tLocalUse\(\d+\)\tNoOccurrence\tConservative\tUnknown\tnone/.test(facts)],
  ["source analysis retains nonlocal unreachable value", /unreachableNonLocal\tvalue\tNonLocalUse\tUnreachablePath\tConservative\tUnknown\tnone/.test(facts)],
];

let failed = 0;
for (const [label, pass] of checks) {
  if (!pass) failed++;
  console.log(`${pass ? "PASS" : "FAIL"} ${label}: observed=${pass}`);
}
if (Bun.argv.includes("--negative-control")) {
  const temp = mkdtempSync(join(tmpdir(), "kotlin-local-proof-mutation-"));
  try {
    const originalOperation = 'return local.read("present")';
    const mutatedOperation = 'return local?.read("present")!!';
    const nestedOperation = 'return value.read("nested")';
    const nestedMutation = 'return value?.read("nested")!!';
    const changed = ops.replace(originalOperation, mutatedOperation).replace(nestedOperation, nestedMutation);
    const mutationApplied = changed !== ops && changed.includes(mutatedOperation) && changed.includes(nestedMutation);
    writeFileSync(join(temp, "LocalPresenceOps.kt"), changed);
    const mutated = readFileSync(join(temp, "LocalPresenceOps.kt"), "utf8");
    const baselineDecision = present.includes(originalOperation);
    const mutatedDecision = functionBlock(mutated, "presentLocal").includes(originalOperation);
    const nestedBaselineDecision = nested.includes(nestedOperation);
    const nestedMutatedDecision = functionBlock(mutated, "nestedLiteral").includes(nestedOperation);
    const expectedBaseline = true;
    const expectedMutant = false;
    console.log(`NEGCTRL direct-access decision: expected=${expectedBaseline} observed=${baselineDecision}`);
    console.log(`NEGCTRL mutated safe-call decision: expected=${expectedMutant} observed=${mutatedDecision}; operation=${mutatedOperation}`);
    console.log(`NEGCTRL nested direct-access decision: expected=${expectedBaseline} observed=${nestedBaselineDecision}`);
    console.log(`NEGCTRL nested safe-call decision: expected=${expectedMutant} observed=${nestedMutatedDecision}; operation=${nestedMutation}`);
    if (failed > 0 || !mutationApplied || baselineDecision !== expectedBaseline || mutatedDecision !== expectedMutant
        || nestedBaselineDecision !== expectedBaseline || nestedMutatedDecision !== expectedMutant) process.exit(2);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
} else if (failed > 0) {
  process.exit(1);
}
