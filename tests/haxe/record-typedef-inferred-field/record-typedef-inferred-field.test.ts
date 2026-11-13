import { expect, test } from "bun:test";

// Regression for the record-typedef shape lookup on the Dart and Swift
// backends (board t-mwficz03-x636). tiqian's toPlanWithDiagnostics pushes an
// object literal whose name field is a Null<String> local guarded by
// "!= null" while the typedef declares name:String. The typer accepts the
// literal against the typedef, but the anonymous structure keeps the Null
// wrapper, so its printed signature differs from the registered one and the
// exact-shape lookup missed with "object literal must be typed by a named
// record typedef".
//
// The fix routes that miss through the unification fallback the Rust and
// Kotlin backends already use (PolicyQueries.matchStructTypedefDefByUnification).
// Three arms:
//   positive  -- the tiqian shape generates for both targets, emits the named
//                record constructors, and typechecks (dart analyze / swiftc).
//   ambiguous -- a doubled-Null field unifies with two registered typedefs, so
//                generation must still fail; the fallback refuses, with no
//                silent pick between the two.
//   single    -- the same literal with the rival typedef removed generates, so
//                the ambiguous failure is the ambiguity guard and not a blanket
//                rejection of the shape.
const root = import.meta.dir + "/../../..";
const out =
  Bun.env.BORING_RECORD_TYPEDEF_OUT ??
  root + "/out/record-typedef-inferred-field/test-" + crypto.randomUUID();

const RECORD_ERROR = "object literal must be typed by a named record typedef";

type Result = { code: number | null; stdout: string; stderr: string };

function run(command: Array<string>): Result {
  const result = Bun.spawnSync(command, { cwd: root, stdout: "pipe", stderr: "pipe" });
  return { code: result.exitCode, stdout: result.stdout.toString(), stderr: result.stderr.toString() };
}

/** Generate one target into <dir>/<target>-gen; defines are extra -D values. */
function generate(target: string, dir: string, defines: Array<string>): Result {
  const command = [
    "haxe",
    "tests/haxe/record-typedef-inferred-field/" + target + ".hxml",
    "-D", target + "-output=" + dir + "/" + target + "-gen",
    "-D", target + "-test-output=" + dir + "/" + target + "-gen-tests",
  ];
  for (const define of defines) command.push("-D", define);
  return run(command);
}

test("a Null-wrapped literal field resolves to its named record typedef", async () => {
  const dir = out + "/positive";

  const dart = generate("dart", dir, []);
  expect(dart.code, "dart generation: " + (dart.stderr || dart.stdout)).toBe(0);
  const swift = generate("swift", dir, []);
  expect(swift.code, "swift generation: " + (swift.stderr || swift.stdout)).toBe(0);

  // The literal lowers to the named record with no positional anonymous value.
  const dartSource = await Bun.file(dir + "/dart-gen/lib/exposed/records.dart").text();
  expect(dartSource, "dart capability literal lowers to CapabilityIssue").toContain(
    "CapabilityIssue(issue, d.reason, d.rangeStart, d.rangeEnd)",
  );
  expect(dartSource, "dart envelope literal lowers to its named records").toContain(
    "PlanEnvelope(plan, Diagnostics(capabilityIssues, advanceSuspects))",
  );

  const swiftSource = await Bun.file(dir + "/swift-gen/exposed/Records.swift").text();
  expect(swiftSource, "swift capability literal lowers to CapabilityIssue").toContain(
    "CapabilityIssue(name: issue, reason: d.reason, rangeStart: d.rangeStart, rangeEnd: d.rangeEnd)",
  );
  expect(swiftSource, "swift envelope literal lowers to its named records").toContain(
    "PlanEnvelope(plan: plan, diagnostics: Diagnostics(capabilityIssues: capabilityIssues, advanceSuspects: advanceSuspects))",
  );

  // The emitted tree must typecheck, so the nullable field is accepted by each
  // target and the check goes beyond generation.
  const dartBinary = Bun.which("dart");
  if (dartBinary === null) {
    process.stderr.write("dart not on PATH: dart typecheck environment-not-reached");
  } else {
    const analyze = run([dartBinary, "analyze", "--no-fatal-warnings", dir + "/dart-gen"]);
    expect(analyze.code, "dart analyze: " + (analyze.stdout || analyze.stderr)).toBe(0);
  }

  const swiftBinary = Bun.which("swiftc");
  if (swiftBinary === null) {
    process.stderr.write("swiftc not on PATH: swift typecheck environment-not-reached");
  } else {
    const swiftGen = dir + "/swift-gen";
    const files = Array.from(new Bun.Glob("**/*.swift").scanSync({ cwd: swiftGen })).sort();
    expect(files.length, "swift generation emitted sources").toBeGreaterThan(0);
    const typecheck = run([swiftBinary, "-typecheck", ...files.map((file) => swiftGen + "/" + file)]);
    expect(typecheck.code, "swiftc -typecheck: " + (typecheck.stderr || typecheck.stdout)).toBe(0);
  }
}, 300_000);

test("a literal that two registered typedefs fit is still refused", async () => {
  for (const target of ["dart", "swift"]) {
    const ambiguous = generate(target, out + "/ambiguous", ["record_typedef_ambiguous"]);
    expect(ambiguous.code, target + " must refuse the ambiguous literal").not.toBe(0);
    expect(
      ambiguous.stderr + ambiguous.stdout,
      target + " refusal names the record-typedef error",
    ).toContain(RECORD_ERROR);

    const single = generate(target, out + "/single", ["record_typedef_ambiguous", "record_typedef_single"]);
    expect(
      single.code,
      target + " single-candidate generation: " + (single.stderr || single.stdout),
    ).toBe(0);
  }
}, 300_000);
