import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/**
 * Feature spec 24: every target compiler writes the package manifest of
 * its generated tree, on by default with a one-define opt-out. The
 * TypeScript lane is exercised end to end here: a temp generation with a
 * relative runtime import produces a package.json whose tree a consumer
 * program runs under bun without any repository assistance. The Swift,
 * Kotlin, and Rust manifests carry no runnable toolchain in this
 * repository (swiftc without swift build, no Gradle), so their bytes are
 * pinned; cargo exercises the Rust manifest through the workspace.
 */

const REPO_ROOT = path.resolve(import.meta.dir, "../..");

interface GenerationOptions {
  tsOutput: string;
  testOutput: string;
  runtimeImport?: string;
  packageShell?: string;
}

interface CompilerOutcome {
  exitCode: number;
  stderr: string;
}

/**
 * Rewrites examples/ts.hxml for one generation: output trees go to the
 * given directories, the runtime import and the shell define follow the
 * scenario. An undefined packageShell drops the repository's opt-out so
 * the default emission runs.
 */
function rewriteHxml(source: string, opts: GenerationOptions): string {
  let out = source
    .replace("-D ts-test-output=reference/ts/gen-tests", `-D ts-test-output=${opts.testOutput}`)
    .replace("-D ts-output=reference/ts/gen", `-D ts-output=${opts.tsOutput}`);
  if(opts.runtimeImport !== undefined) {
    out = out.replace("-D runtime-import=@boring/runtime", `-D runtime-import=${opts.runtimeImport}`);
  }
  if(opts.packageShell === undefined) {
    out = out.replace("-D package-shell=none\n", "");
  } else {
    out = out.replace("-D package-shell=none", `-D package-shell=${opts.packageShell}`);
  }
  return out;
}

/** Runs one rewritten generation and reports the compiler outcome. */
async function runHaxe(hxmlName: string, content: string): Promise<CompilerOutcome> {
  const hxmlPath = path.join(REPO_ROOT, "out", hxmlName);
  fs.mkdirSync(path.dirname(hxmlPath), { recursive: true });
  fs.writeFileSync(hxmlPath, content);
  const proc = Bun.spawn(["haxe", path.relative(REPO_ROOT, hxmlPath)], {
    cwd: REPO_ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
  return { exitCode, stderr };
}

function tempTree(label: string): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), `boring-shell-${label}-`));
}

const DEFAULT_PACKAGE_JSON = [
  "{",
  '  "name": "generated",',
  '  "version": "0.1.0",',
  '  "private": true,',
  '  "type": "module",',
  '  "exports": {',
  '    "./boring/*": "./boring/*.ts",',
  '    "./runtime": "./runtime.ts",',
  '    "./std/*": "./std/*.ts",',
  '    "./tests/*": "./tests/*.ts"',
  "  },",
  '  "devDependencies": {',
  '    "typescript": "^5.9.0"',
  "  }",
  "}",
  "",
].join("\n");

const IDENTITY_PACKAGE_JSON = [
  "{",
  '  "name": "boring-demo",',
  '  "version": "9.9.9",',
  '  "license": "Apache-2.0",',
  '  "private": true,',
  '  "type": "module",',
  '  "exports": {',
  '    "./boring/*": "./boring/*.ts",',
  '    "./runtime": "./runtime.ts",',
  '    "./std/*": "./std/*.ts",',
  '    "./tests/*": "./tests/*.ts"',
  "  },",
  '  "devDependencies": {',
  '    "typescript": "^5.9.0"',
  "  }",
  "}",
  "",
].join("\n");

describe("package shell emission", () => {
  test("default emission writes package.json and the tree runs standalone", async () => {
    const tree = tempTree("default");
    try {
      const hxml = rewriteHxml(fs.readFileSync(path.join(REPO_ROOT, "examples/ts.hxml"), "utf8"), {
        tsOutput: tree,
        testOutput: path.join(tree, "../boring-shell-default-tests"),
        runtimeImport: "./runtime",
      });
      const result = await runHaxe("package-shell-default.hxml", hxml);
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);

      expect(fs.readFileSync(path.join(tree, "package.json"), "utf8")).toBe(DEFAULT_PACKAGE_JSON);
      // The runtime import resolves per file against the tree the
      // compilation wrote: a nested module walks up to the root entry.
      expect(fs.readFileSync(path.join(tree, "boring/Fp32.ts"), "utf8")).toContain('from "../runtime.ts"');

      fs.writeFileSync(path.join(tree, "consumer.ts"), [
        'import { Fp32 } from "./boring/Fp32.ts";',
        "const bits = Fp32.toBits(1.5);",
        'if(bits !== 0x3fc00000) { throw new Error("bad bits: " + bits); }',
        'if(Fp32.fromBits(0x3fc00000) !== 1.5) { throw new Error("bad value"); }',
        'console.log("consumer-ok");',
        "",
      ].join("\n"));
      const consumer = Bun.spawn(["bun", "consumer.ts"], { cwd: tree, stdout: "pipe", stderr: "pipe" });
      const [consumerCode, consumerOut, consumerErr] = await Promise.all([
        consumer.exited,
        new Response(consumer.stdout).text(),
        new Response(consumer.stderr).text(),
      ]);
      expect(consumerErr).toBe("");
      expect(consumerCode).toBe(0);
      expect(consumerOut.trim()).toBe("consumer-ok");

      // The exports map resolves the package by name: a symlinked
      // node_modules entry routes "generated/boring/Fp32" through the
      // directory wildcard to the emitted .ts file.
      fs.mkdirSync(path.join(tree, "node_modules"));
      fs.symlinkSync(tree, path.join(tree, "node_modules", "generated"));
      fs.writeFileSync(path.join(tree, "consumer-pkg.ts"), [
        'import { Fp32 } from "generated/boring/Fp32";',
        'import { doubleToI64 } from "generated/runtime";',
        'if(doubleToI64(1.5).low !== 0) { throw new Error("bad runtime export"); }',
        'console.log("consumer-pkg-ok");',
        "",
      ].join("\n"));
      const pkgConsumer = Bun.spawn(["bun", "consumer-pkg.ts"], { cwd: tree, stdout: "pipe", stderr: "pipe" });
      const [pkgCode, pkgOut, pkgErr] = await Promise.all([
        pkgConsumer.exited,
        new Response(pkgConsumer.stdout).text(),
        new Response(pkgConsumer.stderr).text(),
      ]);
      expect(pkgErr).toBe("");
      expect(pkgCode).toBe(0);
      expect(pkgOut.trim()).toBe("consumer-pkg-ok");
    } finally {
      fs.rmSync(tree, { recursive: true, force: true });
      fs.rmSync(path.join(tree, "../boring-shell-default-tests"), { recursive: true, force: true });
    }
  });

  test("identity defines flow into the manifest", async () => {
    const tree = tempTree("identity");
    try {
      const base = rewriteHxml(fs.readFileSync(path.join(REPO_ROOT, "examples/ts.hxml"), "utf8"), {
        tsOutput: tree,
        testOutput: path.join(tree, "../boring-shell-identity-tests"),
        runtimeImport: "./runtime",
      });
      const hxml = base.replace(
        "-D runtime-emit=.",
        "-D runtime-emit=.\n-D package-name=boring-demo\n-D package-version=9.9.9\n-D package-license=Apache-2.0",
      );
      const result = await runHaxe("package-shell-identity.hxml", hxml);
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);
      expect(fs.readFileSync(path.join(tree, "package.json"), "utf8")).toBe(IDENTITY_PACKAGE_JSON);
    } finally {
      fs.rmSync(tree, { recursive: true, force: true });
      fs.rmSync(path.join(tree, "../boring-shell-identity-tests"), { recursive: true, force: true });
    }
  });

  test("package-shell=none writes source only", async () => {
    const tree = tempTree("off");
    try {
      const hxml = rewriteHxml(fs.readFileSync(path.join(REPO_ROOT, "examples/ts.hxml"), "utf8"), {
        tsOutput: tree,
        testOutput: path.join(tree, "../boring-shell-off-tests"),
        runtimeImport: "./runtime",
        packageShell: "none",
      });
      const result = await runHaxe("package-shell-off.hxml", hxml);
      expect(result.stderr).toBe("");
      expect(result.exitCode).toBe(0);
      expect(fs.existsSync(path.join(tree, "package.json"))).toBe(false);
      expect(fs.existsSync(path.join(tree, "boring/Fp32.ts"))).toBe(true);
    } finally {
      fs.rmSync(tree, { recursive: true, force: true });
      fs.rmSync(path.join(tree, "../boring-shell-off-tests"), { recursive: true, force: true });
    }
  });

  test("an invalid package-shell value aborts the compile", async () => {
    const tree = tempTree("invalid");
    try {
      const hxml = rewriteHxml(fs.readFileSync(path.join(REPO_ROOT, "examples/ts.hxml"), "utf8"), {
        tsOutput: tree,
        testOutput: path.join(tree, "../boring-shell-invalid-tests"),
        runtimeImport: "./runtime",
        packageShell: "bogus",
      });
      const result = await runHaxe("package-shell-invalid.hxml", hxml);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package-shell accepts emit or none");
    } finally {
      fs.rmSync(tree, { recursive: true, force: true });
      fs.rmSync(path.join(tree, "../boring-shell-invalid-tests"), { recursive: true, force: true });
    }
  });

  test("a by-name runtime import with an emitted manifest aborts the compile", async () => {
    const tree = tempTree("byname");
    try {
      // The repository's own by-name import kept in place of the opt-out:
      // the manifest cannot declare the package coordinate it names.
      const hxml = rewriteHxml(fs.readFileSync(path.join(REPO_ROOT, "examples/ts.hxml"), "utf8"), {
        tsOutput: tree,
        testOutput: path.join(tree, "../boring-shell-byname-tests"),
      });
      const result = await runHaxe("package-shell-byname.hxml", hxml);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toContain("package shell requires a relative runtime import");
    } finally {
      fs.rmSync(tree, { recursive: true, force: true });
      fs.rmSync(path.join(tree, "../boring-shell-byname-tests"), { recursive: true, force: true });
    }
  });

  test("the Swift, Kotlin, and Rust manifests of the reference trees are pinned", () => {
    expect(fs.readFileSync(path.join(REPO_ROOT, "reference/swift/gen/Package.swift"), "utf8")).toBe([
      "// Generated by the reflaxe Swift target. Do not edit.",
      "// swift-tools-version:5.9",
      "import PackageDescription",
      "",
      "let package = Package(",
      '    name: "generated",',
      "    targets: [",
      "        .target(",
      '            name: "generated",',
      '            path: ".",',
      "            sources: [",
      '                "Runtime.swift",',
      '                "boring",',
      '                "std",',
      '                "tests",',
      "            ]",
      "        )",
      "    ]",
      ")",
      "",
    ].join("\n"));

    expect(fs.readFileSync(path.join(REPO_ROOT, "reference/kotlin/gen/build.gradle.kts"), "utf8")).toBe([
      "// Generated by the reflaxe Kotlin target. Do not edit.",
      "plugins {",
      '    kotlin("jvm") version "2.4.10"',
      "}",
      "",
      "repositories {",
      "    mavenCentral()",
      "}",
      "",
      "sourceSets {",
      "    main {",
      '        kotlin.srcDir(".")',
      "    }",
      "}",
      "",
    ].join("\n"));

    expect(fs.readFileSync(path.join(REPO_ROOT, "reference/rust-gen/src/Cargo.toml"), "utf8")).toBe([
      "# Generated by the reflaxe Rust target. Do not edit.",
      "[package]",
      'name = "boring-codec-gen"',
      'version = "0.1.0"',
      'license = "MIT"',
      'edition = "2024"',
      "autotests = false",
      "",
      "[lib]",
      'path = "lib.rs"',
      "",
      "[[test]]",
      'name = "vector_gen"',
      'path = "../../../tests/rust/vector_gen.rs"',
      "",
    ].join("\n"));

    expect(fs.readFileSync(path.join(REPO_ROOT, "reference/rust-f32-gen/src/Cargo.toml"), "utf8")).toBe([
      "# Generated by the reflaxe Rust target. Do not edit.",
      "[package]",
      'name = "boring-codec-f32-gen"',
      'version = "0.1.0"',
      'license = "MIT"',
      'edition = "2024"',
      "autotests = false",
      "",
      "[lib]",
      'path = "lib.rs"',
      "",
      "[[test]]",
      'name = "vector_gen_f32"',
      'path = "../../../tests/rust/vector_gen_f32.rs"',
      "",
    ].join("\n"));
  });
});
