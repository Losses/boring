import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const root = path.resolve(__dirname, "../..");

function generated(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

describe("TTry catch-site lowering", () => {
  test("uses native typed catch forms on every target", () => {
    const ts = generated("reference/ts/gen/boring/TryOps.ts");
    const kotlin = generated("reference/kotlin/gen/boring/TryOps.kt");
    const rust = generated("reference/rust-gen/src/boring/try_ops.rs");
    const swift = generated("reference/swift/gen/boring/TryOps.swift");
    const dart = generated("reference/dart/gen/lib/boring/try_ops.dart");

    expect(ts).toContain("error instanceof VectorException");
    expect(ts).toContain("throw error;");
    expect(kotlin).toContain("catch (error: VectorException)");
    expect(rust).toContain("Result<(), VectorError>");
    expect(rust).toContain("Err(error) =>");
    expect(swift).toContain("catch let error as VectorException");
    expect(swift).toContain("catch {");
    expect(dart).toContain("on vector_exception.VectorException catch (error)");
  });
});
