import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Regression fixture for the Dart generated tree's runtime import depth
 * (task t-muviv6in-y1qx, parent t-mum2ad8j-wgf4).
 *
 * The evidence tree at boring/out/try-tail/ev-20261005T1717 recorded
 * `dart analyze` reporting URI_DOES_NOT_EXIST for
 * `../../platform_host.dart` and `../../runtime.dart` inside
 * `lib/trytail/try_tail_oracle.dart`, and `dart run` failing with
 * rc 254. The emitter wrote the runtime and the synthesized platform host
 * at the output-tree root while every generated library sits under
 * `lib/`; a Dart library under `lib/` may not import a relative URI
 * that climbs above `lib/`, so each import was one `..` too deep.
 *
 * This case generates the minimal fixture (one library that references
 * both files) and pins the invariant: the runtime files are emitted under
 * `lib/` beside the modules, and no relative import from a generated
 * library escapes `lib/` or fails to resolve. It fails on the pre-fix
 * tree and passes on the fixed one; it needs no Dart toolchain, so the
 * regression is visible wherever haxe runs.
 */
const root = path.resolve(__dirname, "../..");
const outRoot = "out/dart-runtime-import-depth";
const tree = path.join(root, outRoot, "gen/dart");
const lib = path.join(tree, "lib");
const probe = path.join(lib, "depth/runtime_import_depth_probe.dart");

function walk(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}

describe("Dart runtime import depth", () => {
  test("generated libraries import the runtime from inside lib/, never above it", async () => {
    fs.rmSync(path.join(root, outRoot), { recursive: true, force: true });
    const proc = Bun.spawn(
      [
        "haxe",
        "tests/haxe/dart-runtime-import-depth/gen/dart.hxml",
        "-D",
        `dart-output=${outRoot}/gen/dart`,
        "-D",
        `dart-test-output=${outRoot}/gen/dart-tests`,
      ],
      { cwd: root, stdout: "pipe", stderr: "pipe" },
    );
    const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
    expect(exitCode, stderr).toBe(0);

    // The runtime files sit beside the modules under lib/. A copy at the
    // output-tree root is unreachable from lib/.
    expect(fs.existsSync(path.join(lib, "runtime.dart")), "lib/runtime.dart missing").toBe(true);
    expect(fs.existsSync(path.join(lib, "platform_host.dart")), "lib/platform_host.dart missing").toBe(true);
    expect(fs.existsSync(path.join(tree, "runtime.dart")), "runtime.dart must not sit above lib/").toBe(false);
    expect(fs.existsSync(path.join(tree, "platform_host.dart")), "platform_host.dart must not sit above lib/").toBe(false);

    const generated = fs.readFileSync(probe, "utf8");
    expect(generated).toContain("import '../runtime.dart' as runtime;");
    expect(generated).toContain("import '../platform_host.dart' as platform_host;");

    // Every relative import in the tree stays under lib/ and resolves.
    // The escaped `../../runtime.dart` of the pre-fix tree resolves to a
    // file above lib/ and fails both teeth.
    for (const file of walk(lib)) {
      if (!file.endsWith(".dart")) continue;
      const source = fs.readFileSync(file, "utf8");
      for (const match of source.matchAll(/^import '([^']+)'/gmu)) {
        const specifier = match[1];
        if (specifier.startsWith("dart:") || specifier.startsWith("package:")) continue;
        const resolved = path.resolve(path.dirname(file), specifier);
        const relative = path.relative(lib, resolved);
        expect(
          relative.startsWith(".."),
          `${path.relative(tree, file)}: import '${specifier}' escapes lib/`,
        ).toBe(false);
        expect(
          fs.existsSync(resolved),
          `${path.relative(tree, file)}: import '${specifier}' does not resolve`,
        ).toBe(true);
      }
    }
  }, 120_000);
});
