import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("default argument expansion generated tree", () => {
  const tsGenDir = path.resolve(__dirname, "../../reference/ts/gen");
  const kotlinGenDir = path.resolve(__dirname, "../../reference/kotlin/gen");
  const rustGenDir = path.resolve(__dirname, "../../reference/rust-gen/src");

  test("TS generated tree emits full-arity calls and clean method signatures", () => {
    const tsFile = path.join(tsGenDir, "boring/DefaultArgsOps.ts");
    expect(fs.existsSync(tsFile)).toBe(true);
    const content = fs.readFileSync(tsFile, "utf8");

    // Method signatures carry no default argument syntax or optional question mark
    expect(content).toContain("public static greet(name: string, prefix: string): string");
    expect(content).toContain("public static configure(base: number, offset: number, scale: number, flag: boolean): number");
    expect(content).toContain("public formatLabel(label: string | null, sep: string): string");
    expect(content).toContain("public static describeTag(tag: string, detail: string | null): string");
    expect(content).toContain("public static openMode(id: number, mode: Mode): string");
    expect(content).toContain("public static adjust(value: number, step: number): number");

    // Call sites are fully expanded to full arity with compiler-inserted default constants
    expect(content).toContain('return DefaultArgsOps.greet("Ada", "Hello");');
    expect(content).toContain("return DefaultArgsOps.configure(100, 20, 1.5, true);");
    expect(content).toContain("return DefaultArgsOps.configure(100, 20, 2.5, true);");
    expect(content).toContain("return DefaultArgsOps.configure(100, 10, 2.5, true);");
    expect(content).toContain('return ops.formatLabel("item", "-");');
    expect(content).toContain('return ops.formatLabel(null, "-");');
    expect(content).toContain('return DefaultArgsOps.describeTag("alpha", null);');
    expect(content).toContain('return DefaultArgsOps.openMode(1, { kind: "Read" });');
    expect(content).toContain("return DefaultArgsOps.adjust(20.0, -5.0);");
    expect(content).toContain("return localAdd(x, 100);");
    expect(content).toContain("return localAdd(x, 200);");
    expect(content).toContain('return greeter.say("Sam", "User");');
  });

  test("Kotlin generated tree emits full-arity calls and clean method signatures", () => {
    const ktFile = path.join(kotlinGenDir, "boring/DefaultArgsOps.kt");
    expect(fs.existsSync(ktFile)).toBe(true);
    const content = fs.readFileSync(ktFile, "utf8");

    // Method signatures carry no default parameter initializers
    expect(content).toContain("fun greet(name: String, prefix: String): String");
    expect(content).toContain("fun configure(base: Int, offset: Int, scale: Double, flag: Boolean): Double");
    expect(content).toContain("fun formatLabel(label: String?, sep: String): String");
    expect(content).toContain("fun describeTag(tag: String, detail: String?): String");
    expect(content).toContain("fun openMode(id: Int, mode: Mode): String");
    expect(content).toContain("fun adjust(value: Double, step: Double): Double");

    // Call sites are fully expanded to full arity
    expect(content).toContain('return DefaultArgsOps.greet("Ada", "Hello")');
    expect(content).toContain("return DefaultArgsOps.configure(100, 20, 1.5, true)");
    expect(content).toContain("return DefaultArgsOps.configure(100, 20, 2.5, true)");
    expect(content).toContain("return DefaultArgsOps.configure(100, 10, 2.5, true)");
    expect(content).toContain('return ops.formatLabel("item", "-")');
    expect(content).toContain('return ops.formatLabel(null, "-")');
    expect(content).toContain('return DefaultArgsOps.describeTag("alpha", null)');
    expect(content).toContain("return DefaultArgsOps.openMode(1, Mode.Read)");
    expect(content).toContain("return DefaultArgsOps.adjust(20.0, -5.0)");
    expect(content).toContain("return localAdd(x, 100)");
    expect(content).toContain("return localAdd(x, 200)");
    expect(content).toContain('return greeter.say("Sam", "User")');
  });

  test("Rust generated tree emits full-arity calls and clean method signatures", () => {
    const rsFile = path.join(rustGenDir, "boring/default_args_ops.rs");
    expect(fs.existsSync(rsFile)).toBe(true);
    const content = fs.readFileSync(rsFile, "utf8");

    // Method signatures carry clean typed parameter lists
    expect(content).toContain("pub fn greet(name: &str, prefix: &str) -> String");
    expect(content).toContain("pub fn configure(base: u32, offset: u32, scale: f64, flag: bool) -> f64");
    expect(content).toContain("pub fn format_label(&self, label: Option<String>, sep: &str) -> String");
    expect(content).toContain("pub fn describe_tag(tag: &str, detail: Option<String>) -> String");
    expect(content).toContain("pub fn open_mode(id: u32, mode: Mode) -> String");
    expect(content).toContain("pub fn adjust(value: f64, step: f64) -> f64");

    // Call sites are fully expanded to full arity
    expect(content).toContain('return DefaultArgsOps::greet(&"Ada", &"Hello");');
    expect(content).toContain("return DefaultArgsOps::configure(100, 20, 1.5, true);");
    expect(content).toContain("return DefaultArgsOps::configure(100, 20, 2.5, true);");
    expect(content).toContain("return DefaultArgsOps::configure(100, 10, 2.5, true);");
    expect(content).toContain('return ops.format_label(Some("item".to_string()), &"-");');
    expect(content).toContain('return ops.format_label(None, &"-");');
    expect(content).toContain('return DefaultArgsOps::describe_tag(&"alpha", None);');
    expect(content).toContain("return DefaultArgsOps::open_mode(1, Mode::Read);");
    expect(content).toContain("return DefaultArgsOps::adjust(20.0, -5.0);");
    expect(content).toContain("return local_add(x, 100);");
    expect(content).toContain("return local_add(x, 200);");
    expect(content).toContain('return greeter.say(&"Sam", &"User");');
  });
});
