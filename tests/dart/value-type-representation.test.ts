import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

/**
 * Regression fixture for value-type representation reads (task
 * t-mwj0u89s-xc1m).
 *
 * Haxe lowers an inline accessor that returns `this` to `cast wrapper`. The
 * unbox applies in the positions that demand the representation (argument,
 * return, initializer, assignment) and never inside an operator body, where
 * the operand stays the wrapper. Both directions are pinned here.
 */
const root = path.resolve(__dirname, "../..");
const outRoot = "out/dart-value-type-representation";
const tree = path.join(root, outRoot, "gen/dart");
const valueType = path.join(tree, "lib/pub/face_ref.dart");
const consumer = path.join(tree, "lib/pub/face_ref_consumer.dart");

describe("Dart value-type representation reads", () => {
  test("an inlined accessor read in an argument position names the field", async () => {
    fs.rmSync(path.join(root, outRoot), { recursive: true, force: true });
    const proc = Bun.spawn(
      [
        "haxe",
        "tests/haxe/dart-value-type-representation/gen/dart.hxml",
        "-D",
        `dart-output=${outRoot}/gen/dart`,
        "-D",
        `dart-test-output=${outRoot}/gen/dart-tests`,
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect(exitCode, stderr).toBe(0);

    expect(fs.readFileSync(valueType, "utf8")).toContain("extension type FaceRef(String value) {");
    expect(fs.readFileSync(consumer, "utf8")).toContain("_label(ref.value)");
  }, 120000);

  test("an operator body keeps the wrapper", () => {
    withTargetTree("dart", "tests/dart/value-type-representation.test.ts", () => {
      const ops = fs.readFileSync(path.join(root, "reference/dart/gen/lib/boring/value_type_ops.dart"), "utf8");
      const opsConsumer = fs.readFileSync(
        path.join(root, "reference/dart/gen-tests/boring/value_type_consumer.dart"),
        "utf8",
      );
      // The inlined operator body reads both operands as the representation...
      expect(ops).toContain("return Ic(count + other.count);");
      // ...and the call site keeps the wrapper, so the declared operator applies.
      expect(opsConsumer).toContain("final total = first + value_type_ops.Ic.ZERO;");
      expect(opsConsumer).not.toContain("first.count + value_type_ops.Ic.ZERO");
    });
  });
});
