import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("record copy generated tree", () => {
  const tsGenDir = path.resolve(__dirname, "../../reference/ts/gen");
  const kotlinGenDir = path.resolve(__dirname, "../../reference/kotlin/gen");
  const rustGenDir = path.resolve(__dirname, "../../reference/rust-gen/src");

  test("TS generated tree emits object literals with fields in declaration order", () => {
    const tsFile = path.join(tsGenDir, "boring/RecordOps.ts");
    expect(fs.existsSync(tsFile)).toBe(true);
    const content = fs.readFileSync(tsFile, "utf8");

    // Single override keeps field declaration order
    expect(content).toContain("return { id: item.id, name: item.name, score: newScore, active: item.active };");

    // Reordered overrides in macro call site fold into declaration order
    expect(content).toContain("return { id: item.id, name: newName, score: item.score, active: newActive };");

    // Multiple overrides fold into declaration order
    expect(content).toContain("return { id: newId, name: newName, score: newScore, active: item.active };");
  });

  test("Kotlin generated tree emits named constructor calls in declaration order", () => {
    const ktFile = path.join(kotlinGenDir, "boring/RecordOps.kt");
    expect(fs.existsSync(ktFile)).toBe(true);
    const content = fs.readFileSync(ktFile, "utf8");

    expect(content).toContain("return ItemRecord(id = item.id, name = item.name, score = newScore, active = item.active)");
    expect(content).toContain("return ItemRecord(id = item.id, name = newName, score = item.score, active = newActive)");
    expect(content).toContain("return ItemRecord(id = newId, name = newName, score = newScore, active = item.active)");
  });

  test("Rust generated tree emits struct instantiation in declaration order", () => {
    const rsFile = path.join(rustGenDir, "boring/record_ops.rs");
    expect(fs.existsSync(rsFile)).toBe(true);
    const content = fs.readFileSync(rsFile, "utf8");

    expect(content).toContain("return ItemRecord { id: item.id, name: item.name.clone(), score: new_score, active: item.active };");
    expect(content).toContain("return ItemRecord { id: item.id, name: new_name.to_string(), score: item.score, active: new_active };");
    expect(content).toContain("return ItemRecord { id: new_id, name: new_name.to_string(), score: new_score, active: item.active };");
  });
});
