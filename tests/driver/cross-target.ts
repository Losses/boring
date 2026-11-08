// Cross-target driver probe — the assertion half of the run.
//
// Boundary (packages/test/README.md): this file decides pass/fail; the
// execution (boring gen/test per target, probe project materialization) is
// owned by packages/test/bin/driver-probe-runner.ts. Run with:
//   bun run test:driver:cross-target
import { openProbeSession, runBoring } from "../../packages/test/bin/driver-probe-runner.ts";

const targets = ["haxe", "ts", "kotlin", "rust", "swift", "dart"];
const expected = ["tests.DriverPlanTests.hostPlatform", "tests.DriverPlanTests.parse", "tests.DriverPlanTests.generation", "tests.DriverPlanTests.swiftLibrary", "tests.DriverPlanTests.invalidConfig", "tests.DriverPlanTests.sourceSets", "tests.DriverPlanTests.comparison", "tests.DriverPlanTests.testCommands", "tests.DriverPlanTests.packAndEnvironment"];

const session = openProbeSession();
try {
  for (const target of targets) {
    for (const action of ["gen", "test"]) {
      const result = runBoring([action, target, "--project", session.projectFile]);
      if (result.code !== 0) {
        throw new Error(`driver ${action} ${target} failed:\n${result.output}`);
      }
    }
    const records = session.readResults(target);
    for (const id of expected) {
      const record = records.find((item) => item.id === id);
      if (record?.verdict !== "pass") {
        throw new Error(`${target}: ${id} produced ${record?.verdict ?? "no result"}`);
      }
    }
    process.stdout.write(`${target}: ${expected.length} driver probes passed\n`);
  }
} finally {
  session.close();
}
