import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Regression fixture for narrowed local declarations (task t-mwj1rejm-ntwj).
 *
 * A local whose value cannot be null at the declaration must not name a
 * nullable Dart type: the value is returned or passed where the non-null
 * type is demanded. Two shapes reach the declaration:
 *
 *   - a read of a local after a null guard (Dart promotes the read);
 *   - a read of a local the emitter already declared non-null (the
 *     null-guard ternary).
 *
 * The emitter declared both as `double?`, so `dart analyze` failed with
 * return_of_invalid_type / argument_type_not_assignable. This case needs no
 * Dart toolchain.
 */
const root = path.resolve(__dirname, "../..");
const outRoot = "out/dart-narrowed-local-declaration";
const tree = path.join(root, outRoot, "gen/dart");
const ops = path.join(tree, "lib/narrow/narrowed_local_ops.dart");

describe("Dart narrowed local declarations", () => {
  test("locals proven non-null are declared without a nullable type", async () => {
    fs.rmSync(path.join(root, outRoot), { recursive: true, force: true });
    const proc = Bun.spawn(
      [
        "haxe",
        "tests/haxe/dart-narrowed-local-declaration/gen/dart.hxml",
        "-D",
        `dart-output=${outRoot}/gen/dart`,
        "-D",
        `dart-test-output=${outRoot}/gen/dart-tests`,
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect(exitCode, stderr).toBe(0);

    const text = fs.readFileSync(ops, "utf8");
    expect(text).toContain("final double edge = candidate;");
    expect(text).toContain("final double reference = stretch;");
    // The nullable parameters stay nullable; no local declaration may name a
    // nullable type here.
    expect(text).not.toContain("final double? ");
  }, 120000);
});
