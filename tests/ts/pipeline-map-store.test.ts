import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("Dart pipeline map store lowering", () => {
  test("uses growing-list writes in constructor and ordinary pipeline sites", () => {
    const constructor = fs.readFileSync(
      path.resolve(__dirname, "../../reference/dart/gen/lib/boring/constructor_statement_ops.dart"),
      "utf8",
    );
    expect(constructor).toContain("pipeline_result.add(incremented);");
    expect(constructor).not.toContain("pipeline_result[pipeline_index] =");

    const pipeline = fs.readFileSync(
      path.resolve(__dirname, "../../reference/dart/gen/lib/boring/pipeline_ops.dart"),
      "utf8",
    );
    expect(pipeline).toContain("pipeline_result1.add(v * 10);");
  });
});
