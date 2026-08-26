/**
 * Interception harness per docs/specs/style/01-haxe-style-standard.md.
 * Each directory under cases/ holds a Case.hx whose first line names the
 * violation the interception must report:
 *
 *   // expect: V01 IteratorLoop
 *
 * The runner compiles every case with the interception macro guarding that
 * case directory, and asserts the compile aborts with the named violation.
 * V07 ShapeMutation has no fragment: the compiler rejects writes to final
 * fields before typing completes, so the macro row is defense in depth.
 * Run under the flake shell (`nix develop -c bash -c 'bun run
 * test:intercept'`); haxe must be on PATH, exactly like test:haxe.
 */
import { readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";

const repoRoot = new URL("../..", import.meta.url).pathname;
const casesRoot = `${repoRoot}tests/interception/cases`;

let failures = 0;
let passes = 0;

for (const name of readdirSync(casesRoot).sort()) {
  const caseDir = `${casesRoot}/${name}`;
  const source = readFileSync(`${caseDir}/Case.hx`, "utf8");
  const firstLine = source.split("\n")[0] ?? "";
  const expected = firstLine.match(/^\/\/ expect: (V\d+ \w+)/);
  if (expected === null) {
    console.error(`FAIL ${name}: first line must name the expected violation`);
    failures += 1;
    continue;
  }
  const buildFile = `${repoRoot}tests/interception/.tmp-${name}.hxml`;
  const guardPath = `tests/interception/cases/${name}`;
  writeFileSync(
    buildFile,
    [
      "-cp tools/haxe",
      "-cp haxe/src",
      `-cp ${guardPath}`,
      "-main Case",
      "-js out/haxe/intercept-case.js",
      `--macro Intercept.run(['${guardPath}'])`,
      "",
    ].join("\n"),
  );
  try {
    const proc = Bun.spawnSync(["haxe", `tests/interception/.tmp-${name}.hxml`], {
      cwd: repoRoot,
      stdout: "pipe",
      stderr: "pipe",
    });
    const output = `${proc.stdout}` + `${proc.stderr}`;
    const exitCode = proc.exitCode;
    if (exitCode === 0) {
      console.error(`FAIL ${name}: compile succeeded, expected abort`);
      failures += 1;
    } else if (!output.includes(expected[1]!)) {
      console.error(`FAIL ${name}: abort without ${expected[1]}`);
      console.error(output.trim());
      failures += 1;
    } else {
      passes += 1;
      console.log(`pass ${name}`);
    }
  } finally {
    rmSync(buildFile, { force: true });
  }
}

if (failures > 0) {
  console.error(`${failures} interception case(s) failed`);
  process.exit(1);
}
console.log(`all ${passes} interception cases rejected as specified`);
