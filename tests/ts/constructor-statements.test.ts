import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("constructor statement initialization safety", () => {
  test("keeps body locals and lowered temporaries out of the initializer list", () => {
    const file = path.resolve(
      __dirname,
      "../../reference/dart/gen/lib/boring/constructor_statement_ops.dart",
    );
    expect(fs.existsSync(file)).toBe(true);
    const content = fs.readFileSync(file, "utf8");
    const signature = content.match(/ConstructorStatementOps\([^)]*\)([^{]*)\{/);
    expect(signature).not.toBeNull();
    expect(signature![1]).not.toContain("_g");
    expect(signature![1]).not.toContain("mapped");
    expect(content).toContain("this.filled = _g;");
    expect(content).toContain("this.mapped = mapped;");
  });

  test("keeps parameter-to-field assignments represented in the generated constructor", () => {
    const file = path.resolve(
      __dirname,
      "../../reference/dart/gen/lib/boring/constructor_statement_ops.dart",
    );
    const content = fs.readFileSync(file, "utf8");
    expect(content).toContain("ConstructorStatementOps(int count, List<int> values)");
    expect(content).toContain("this.filled = _g;");
  });
});
