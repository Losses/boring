import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

/**
 * Guards the canonical std.Fs host-failure model
 * (docs/specs/stdlib/17-platform-modules.md "Failure behavior").
 *
 * The model spans four layers that a future edit can break independently:
 * the Haxe identity (std.FsError variant-per-kind / std.FsException), the Rust runtime that
 * must carry the failure as a Result instead of panicking, the emitter that
 * must recognize the fallible surface and map it into std.FsError, and the
 * spec text that names the identity. This file reads each layer as text, so
 * it stays hermetic -- it never runs haxe, rustc, or nix. The live readings
 * (rc/stdout/stderr) are the fixture run recorded in the task evidence.
 */

const REPO_ROOT = resolve(import.meta.dir, "..");

function read(path: string): string {
  const full = join(REPO_ROOT, path);
  expect(existsSync(full), `missing ${path} (REPO_ROOT resolved to ${REPO_ROOT})`).toBe(true);
  return readFileSync(full, "utf8");
}

const FALLIBLE = ["readText", "writeText", "appendText", "makeDirs", "readDir", "deleteFile", "rename"];
const KINDS = ["NotFound", "PermissionDenied", "NotDirectory", "IsDirectory", "AlreadyExists", "InvalidInput", "Unavailable", "Other"];

describe("std.Fs failure model", () => {
  test("the Haxe identity is a closed variant-per-kind payload", () => {
    const error = read("samples/std/FsError.hx");
    // One variant per normalized kind; the kind is the variant, so no
    // separate FsKind identity exists (features spec 06 R5).
    for (const k of KINDS) expect(error).toContain(k + "(");
    expect(error).toContain("Unavailable(operation:String, path:String);");
    expect(error).not.toContain("FsKind");
    const exception = read("samples/std/FsException.hx");
    expect(exception).toContain("class FsException extends haxe.Exception");
    expect(exception).toContain("public final error:FsError");
  });

  test("the Rust runtime returns Result and never panics", () => {
    const runtime = read("packages/compiler/reflaxe/rust/rustcompiler/RustRuntime.hx");
    const start = runtime.indexOf("public static final FS_SOURCE");
    const end = runtime.indexOf("\n';", start);
    expect(start, "FS_SOURCE not found").toBeGreaterThan(-1);
    expect(end, "FS_SOURCE terminator not found").toBeGreaterThan(start);
    const shim = runtime.slice(start, end);
    expect(shim).not.toContain("panic!");
    expect(shim).toContain("pub struct FsError");
    // The frozen canonical contract names the raw host text native_detail
    // and leaves it empty for the synthesized Unavailable kind.
    expect(shim).toContain("pub native_detail: UString");
    expect(shim).toContain("FsErrorKind::Unavailable => String::new()");
    expect(shim).toContain("pub enum FsErrorKind");
    expect(shim).toContain("pub fn read_text(path: &UStr) -> Result<UString, FsError>");
    expect(shim).toContain("pub fn write_text(path: &UStr, data: &UStr) -> Result<(), FsError>");
    expect(shim).toContain("pub fn make_dirs(path: &UStr) -> Result<(), FsError>");
    expect(shim).toContain("pub fn read_dir(path: &UStr) -> Result<Vec<UString>, FsError>");
    // The total probes keep their bool shape: a missing path is false, not a failure.
    expect(shim).toContain("pub fn exists(path: &UStr) -> bool");
    expect(shim).toContain("pub fn is_directory(path: &UStr) -> bool");
  });

  test("the emitter recognizes the surface and maps into std.FsError", () => {
    const state = read("packages/compiler/reflaxe/rust/rustcompiler/RustEmissionState.hx");
    expect(state).toContain("public static function stdFsFallibleMember");
    expect(state).toContain('if (module != "std.Fs")');
    for (const op of FALLIBLE) expect(state).toContain(`"${op}"`);

    const expr = read("packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx");
    expect(expr).toContain("RustEmissionState.stdFsFallibleMember(c.get().module, name)");
    expect(expr).toContain("no error-carrying Result slot encloses this call");

    const decl = read("packages/compiler/reflaxe/rust/rustcompiler/RustDecl.hx");
    expect(decl).toContain('cls.module == "std.FsException"');
    expect(decl).toContain("impl From<");
    expect(decl).toContain("optionNamed(options, kind)");
    expect(decl).toContain('hostKind + "::" + kind');
    expect(decl).toContain("fn from(error: ");
    // A declared payload enum with no scanned owner resolves to its own
    // declared module, never the caller's: the error name must have a
    // declaration site in the tree the signature is emitted into.
    expect(decl).toContain("return unique.module;");

    const compiler = read("packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx");
    // The payload enum is co-emitted in the exception module, so the error
    // slot names that module; the declared module is the fallback only.
    expect(compiler).toContain('state.payloadEnumModules.get(RustEmissionState.identityKey("std.FsError", "FsError"))');
    expect(compiler).toContain('mergeEnum(key, {module: emitted != null ? emitted : "std.FsError", name: "FsError"})');
    // A synthetic union that absorbs the failure also needs the direct
    // runtime conversion: a bare `?` from runtime::fs::FsError needs a From
    // the Haxe-facing payload alone does not provide.
    expect(compiler).toContain('runtimePackage + "::fs::FsError> for "');

    // The reference corpus names the identity so the payload enum has a
    // declaration site even when no corpus class catches it.
    expect(read("examples/rust.hxml")).toContain("std.FsException");
  });

  test("the spec names the identity on every affected layer", () => {
    const platform = read("docs/specs/stdlib/17-platform-modules.md");
    expect(platform).toContain("std.FsException");
    expect(platform).toContain("std.FsError");
    expect(platform).toContain("NotFound(operation, path, nativeDetail)");
    expect(platform).toContain("Unavailable(operation, path)");
    expect(read("docs/specs/stdlib/03-haxe-exception.md")).toContain("std.FsException");
    expect(read("docs/specs/features/06-errors-and-results.md")).toContain("std.FsError");
  });

  test("the fixture observes the identity through one catch shape", () => {
    const probe = read("tests/haxe/fs-failure-model/fsprobe/FsFailureProbe.hx");
    expect(probe).toContain("catch (error:FsException)");
    expect(probe).toContain("case NotFound(operation, path, nativeDetail):");
    const harness = read("tests/haxe/fs-failure-model/native/harness.rs");
    expect(harness).toContain("fs_failure_probe_observe");
    expect(harness).toContain("fs_failure_probe_escaped");
  });
});
