import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Regression fixture for the Dart extension-grouping scope (task
 * t-mwj1re1f-becy).
 *
 * docs/specs/features/10-static-extension.md groups every marked extension
 * function over one receiver into a single extension declaration per
 * library. The emitter grouped per class, so two holder classes in one Haxe
 * module declared the same extension name inside one Dart library and
 * `dart analyze` failed with duplicate_definition; the consumer also lost a
 * method to the ambiguity.
 *
 * This case generates the fixture and pins the library-scoped grouping. It
 * needs no Dart toolchain.
 */
const root = path.resolve(__dirname, "../..");
const outRoot = "out/dart-extension-decl-grouping";
const tree = path.join(root, outRoot, "gen/dart");
const holders = path.join(tree, "lib/pub/extension_holders.dart");
const consumer = path.join(tree, "lib/pub/extension_holders_consumer.dart");

describe("Dart extension declaration grouping", () => {
  test("two holder classes in one module share one extension declaration", async () => {
    fs.rmSync(path.join(root, outRoot), { recursive: true, force: true });
    const proc = Bun.spawn(
      [
        "haxe",
        "tests/haxe/dart-extension-decl-grouping/gen/dart.hxml",
        "-D",
        `dart-output=${outRoot}/gen/dart`,
        "-D",
        `dart-test-output=${outRoot}/gen/dart-tests`,
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect(exitCode, stderr).toBe(0);

    const holdersText = fs.readFileSync(holders, "utf8");
    const consumerText = fs.readFileSync(consumer, "utf8");
    const declarations = holdersText.match(/^extension \w+HolderModeExtension on [\w.]+HolderMode \{/gmu) ?? [];
    expect(declarations.length).toBe(1);
    expect(holdersText).toContain("String modeSuffix(String suffix)");
    expect(holdersText).toContain("String modePrefix(String prefix)");
    expect(consumerText).toContain('mode.modePrefix("p:") + "/" + mode.modeSuffix("!")');
    expect(consumerText).not.toMatch(/\bExtensionHolders(?:Extra)?\./u);
  }, 120000);
});
