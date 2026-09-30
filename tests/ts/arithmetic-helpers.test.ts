import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("arithmetic helpers generated tree", () => {
  const tsGenDir = path.resolve(__dirname, "../../reference/ts/gen");
  const kotlinGenDir = path.resolve(__dirname, "../../reference/kotlin/gen");
  const rustGenDir = path.resolve(__dirname, "../../reference/rust/gen");

  test("No standalone Arithmetic or IntRange module is generated in any target", () => {
    expect(fs.existsSync(path.join(tsGenDir, "std/Arithmetic.ts"))).toBe(false);
    expect(fs.existsSync(path.join(tsGenDir, "std/IntRange.ts"))).toBe(false);

    expect(fs.existsSync(path.join(kotlinGenDir, "std/Arithmetic.kt"))).toBe(false);
    expect(fs.existsSync(path.join(kotlinGenDir, "std/IntRange.kt"))).toBe(false);

    expect(fs.existsSync(path.join(rustGenDir, "std/arithmetic.rs"))).toBe(false);
    expect(fs.existsSync(path.join(rustGenDir, "std/int_range.rs"))).toBe(false);
  });

  test("TS inlines arithmetic helpers and abstracts into native comparison operators and ternaries", () => {
    const tsFile = path.join(tsGenDir, "boring/ArithmeticOps.ts");
    expect(fs.existsSync(tsFile)).toBe(true);
    const content = fs.readFileSync(tsFile, "utf8");

    expect(content).not.toContain("Arithmetic.");
    expect(content).not.toContain("IntRange");
    expect(content).toContain("return value >= low && value <= high;");
    expect(content).toContain("return (value < floor ? floor : value);");
    expect(content).toContain("return (value > ceiling ? ceiling : value);");
    expect(content).toContain("return value >= range_start && value <= range_end;");
  });

  test("Kotlin inlines arithmetic helpers into native comparison operators and if-expressions", () => {
    const ktFile = path.join(kotlinGenDir, "boring/ArithmeticOps.kt");
    expect(fs.existsSync(ktFile)).toBe(true);
    const content = fs.readFileSync(ktFile, "utf8");

    expect(content).not.toContain("Arithmetic.");
    expect(content).not.toContain("IntRange");
    expect(content).toContain("return value >= low && value <= high");
    expect(content).toContain("return (if ((value < floor)) floor else value)");
    expect(content).toContain("return (if ((value > ceiling)) ceiling else value)");
    expect(content).toContain("return value >= range_start && value <= range_end");
  });

  test("Rust inlines arithmetic helpers into native comparison operators and if-blocks", () => {
    const rsFile = path.join(rustGenDir, "boring/arithmetic_ops.rs");
    expect(fs.existsSync(rsFile)).toBe(true);
    const content = fs.readFileSync(rsFile, "utf8");

    expect(content).not.toContain("Arithmetic::");
    expect(content).not.toContain("IntRange");
    // The inlined comparisons keep the declared Haxe Int (signed) ordering
    // over the business u32 domain: each operand reinterprets its bits to
    // i32 before the compare (SignedBusinessComparison). A naive u32
    // compare would order -1 above 0, so an empty IntRange 0..-1 would
    // read as containing.
    expect(content).toContain("return (i32::from_ne_bytes(((value) as i32).to_ne_bytes())) >= i32::from_ne_bytes(((low) as i32).to_ne_bytes()) && (i32::from_ne_bytes(((value) as i32).to_ne_bytes())) <= i32::from_ne_bytes(((high) as i32).to_ne_bytes());");
    expect(content).toContain("return if i32::from_ne_bytes(((value) as i32).to_ne_bytes()) < (i32::from_ne_bytes(((floor) as i32).to_ne_bytes())) { floor } else { value };");
    expect(content).toContain("return if i32::from_ne_bytes(((value) as i32).to_ne_bytes()) > (i32::from_ne_bytes(((ceiling) as i32).to_ne_bytes())) { ceiling } else { value };");
    expect(content).toContain("return (i32::from_ne_bytes(((value) as i32).to_ne_bytes())) >= i32::from_ne_bytes(((range_start) as i32).to_ne_bytes()) && (i32::from_ne_bytes(((value) as i32).to_ne_bytes())) <= i32::from_ne_bytes(((range_end) as i32).to_ne_bytes());");
  });
});
