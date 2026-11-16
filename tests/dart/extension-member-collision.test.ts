import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Regression fixture for colliding extension member names (task
 * t-mwj2nzqa-mgcv).
 *
 * A Dart extension cannot overload a member, so two marked extension
 * functions over the same receiver that render one member name cannot share
 * the library's extension declaration. The first declaration (source order)
 * keeps the extension spelling; the later one stays in its declaring class,
 * whose call sites use the class-qualified static form. This case pins the
 * coexistence and needs no Dart toolchain.
 */
const root = path.resolve(__dirname, "../..");
const outRoot = "out/dart-extension-member-collision";
const tree = path.join(root, outRoot, "gen/dart");
const library = path.join(tree, "lib/pub/extension_overloads.dart");
const consumer = path.join(tree, "lib/pub/extension_overloads_consumer.dart");

describe("Dart extension member collision", () => {
  test("the later declaration keeps its class and the call site qualifies it", async () => {
    fs.rmSync(path.join(root, outRoot), { recursive: true, force: true });
    const proc = Bun.spawn(
      [
        "haxe",
        "tests/haxe/dart-extension-member-collision/gen/dart.hxml",
        "-D",
        `dart-output=${outRoot}/gen/dart`,
        "-D",
        `dart-test-output=${outRoot}/gen/dart-tests`,
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect(exitCode, stderr).toBe(0);

    const libraryText = fs.readFileSync(library, "utf8");
    const consumerText = fs.readFileSync(consumer, "utf8");
    // One member merged into the extension, the second kept as a class static.
    expect(libraryText).toContain("String mark() {");
    expect(libraryText).toContain("final class ExtensionOverloadsExtra {");
    expect(libraryText).toContain("static String mark(");
    // The call sites follow the two shapes.
    expect(consumerText).toContain("mode.mark()");
    expect(consumerText).toContain("ExtensionOverloadsExtra.mark(mode, \"!\")");
  }, 120000);
});
