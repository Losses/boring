import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";
import { installTargetTreeReport, withTargetTree } from "../support/target-trees";

installTargetTreeReport(import.meta.path);

const root = path.resolve(__dirname, "../..");

function generated(relative: string): string {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

describe("TTry catch-site lowering", () => {
  test("uses native typed catch forms on every target", () => {
    const ts = generated("reference/ts/gen-tests/boring/TryOps.test.ts");
    const kotlin = generated("reference/kotlin/gen-tests/boring/TryOps.kt");
    const rust = generated("reference/rust/gen/tests/tests/try_tests_support/boring/try_ops.rs");
    const dart = generated("reference/dart/gen-tests/boring/try_ops.dart");

    expect(ts).toContain("error instanceof VectorException");
    expect(ts).toContain("throw error;");
    expect(kotlin).toContain("catch (error: VectorException)");
    expect(rust).toContain("Result<(), VectorError>");
    expect(rust).toContain("Err(error) =>");
    withTargetTree("swift", "try-region: uses native typed catch forms on every target", () => {
      const swift = generated("reference/swift/gen-tests/boring/TryOps.swift");
      expect(swift).toContain("catch let error as VectorException");
      expect(swift).toContain("catch {");
    });
    expect(dart).toContain("on vector_exception.VectorException catch (error)");
  });
});
