import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Guards the node:fs extern file operations against the silent Result drop
 * they had after std.Fs moved to `Result<_, FsError>`
 * (docs/specs/stdlib/17-platform-modules.md "Failure behavior").
 *
 * The extern (mkdirSync / writeFileSync) has no Rust face of its own: both
 * members lower to the same resident file edge as std.Fs, so they must ride
 * the same fallibility inference -- `?` inside an error-carrying function,
 * a compile diagnostic in a position with no Result slot, never a bare
 * statement that drops the failure. Like tests/fs-failure-model.test.ts this
 * file reads the emitter as text and stays hermetic: it never runs haxe or
 * rustc. The generated-file block is a bonus reading when the reference tree
 * happens to be on disk.
 */

const REPO_ROOT = resolve(import.meta.dir, "..");

function read(path: string): string {
  const full = join(REPO_ROOT, path);
  expect(existsSync(full), `missing ${path} (REPO_ROOT resolved to ${REPO_ROOT})`).toBe(true);
  return readFileSync(full, "utf8");
}

const EXTERN_MEMBERS = ["mkdirSync", "writeFileSync"];

describe("node:fs extern fallibility", () => {
  test("the emitter registers both members as host Fs failures", () => {
    const state = read("packages/compiler/reflaxe/rust/rustcompiler/RustEmissionState.hx");
    expect(state).toContain("public static function nodeFsExternFallibleMember(cls:ClassType, name:String):Bool");
    for (const op of EXTERN_MEMBERS) expect(state).toContain(`"${op}"`);
    // The gate matches the lowering condition: the test-trace extern class
    // name or any @:jsRequire binding, exactly as the extern branch dispatches.
    expect(state).toContain("cls.name == \"NodeFileSystem\" || cls.meta.has(\":jsRequire\")");
  });

  test("the extern lowering and the inference reach the same path as std.Fs", () => {
    const expr = read("packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx");
    // The extern branch dispatches on the shared predicate, not a local copy.
    expect(expr).toContain("case TField(_, FStatic(c, cf)) if (RustEmissionState.nodeFsExternFallibleMember(c.get(), cf.get().name)):");
    // Both members append the std.Fs propagation/diagnostic suffix.
    expect(expr).toContain(`"Fs::make_dirs(" + stdStrViewArg(args[0]) + ")" + errorPropagationSuffix(c, cf, true)`);
    expect(expr).toContain(`"Fs::write_text(" + stdStrViewArg(args[0]) + ", " + stdStrViewArg(args[1]) + ")" + errorPropagationSuffix(c, cf, true)`);
    // The suffix treats the extern as a host Fs failure (diagnostic when no slot).
    expect(expr).toContain("|| RustEmissionState.nodeFsExternFallibleMember(c.get(), cf.get().name);");
    expect(expr).toContain("|| RustEmissionState.nodeFsExternFallibleMember(c.get(), name))");
    expect(expr).toContain("no error-carrying Result slot encloses this call");

    // The whole-program fallibility fixpoint must mark the enclosing function
    // fallible with the canonical FsError domain, or the extern call would
    // have no slot to propagate into.
    const compiler = read("packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx");
    expect(compiler).toContain("|| RustEmissionState.nodeFsExternFallibleMember(cc.get(), calleeName)) {");
  });

  test("the generated probe propagates instead of dropping the Result", () => {
    const gen = join(REPO_ROOT, "reference", "rust", "gen", "boring", "node_fs_borrow_ops.rs");
    if (!existsSync(gen)) {
      console.log("reference/rust/gen is absent: run `haxe examples/rust.hxml` for the live reading");
      return;
    }
    const src = readFileSync(gen, "utf8");
    expect(src).toContain("-> Result<UString, FsError>");
    // Each extern statement carries the propagated failure; a bare
    // `Fs::make_dirs(...);` statement is the silent-drop regression.
    for (const call of ["Fs::make_dirs(", "Fs::write_text("]) {
      const line = src.split("\n").find((l) => l.includes(call));
      expect(line, `no generated line for ${call}`).toBeDefined();
      expect(line!.trimEnd().endsWith("?;"), `unpropagated ${call}: ${line}`).toBe(true);
    }
  });
});
