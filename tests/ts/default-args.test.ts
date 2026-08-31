import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

describe("default argument expansion generated tree", () => {
  const tsGenDir = path.resolve(__dirname, "../../reference/ts/gen");
  const kotlinGenDir = path.resolve(__dirname, "../../reference/kotlin/gen");
  const swiftGenDir = path.resolve(__dirname, "../../reference/swift/gen");
  const dartGenDir = path.resolve(__dirname, "../../reference/dart/gen");
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
    expect(content).toContain("public static greetWithPrefix(name: string, prefix: string = name): string");
    expect(content).toContain("public static sizeLabel(items: string[] | null): string");
    expect(content).toContain("public static localeSample(lang: string, fallback: string = (lang === \"en\" ? \"English\" : \"Other\")): string");
    expect(content).toContain("public static methodCallSample(text: string, normalized: string = text.toUpperCase()): string");
    expect(content).toContain("public static staticCallSample(value: number, clamped: number = DefaultArgsOps.clampBase(value)): number");
    expect(content).toContain("public static binarySample(value: number, offset: number = value + 1): number");

    // Coalescing defaults stay native on TypeScript and are omitted at their
    // call sites; their empty containers remain expression-valued.
    expect(content).toContain("constructor(familyNames: string[] = [])");
    expect(content).toContain("public static infinityDefault(value: number = Infinity): number");
    expect(content).toContain("public static mapDefault(value: Map<string, number> = new Map()): Map<string, number>");
    expect(content).toContain("return DefaultArgsOps.infinityDefault();");
    expect(content).toContain("return DefaultArgsOps.mapDefault();");
    expect(content).not.toContain("infinityDefault(null)");
    expect(content).not.toContain("mapDefault(null)");

    // Call sites are fully expanded to full arity with compiler-inserted default constants
    expect(content).toContain('return DefaultArgsOps.greet("Ada", "Hello");');
    expect(content).toContain("return DefaultArgsOps.configure(100, 20, 1.5, true);");
    expect(content).toContain("return DefaultArgsOps.configure(100, 20, 2.5, true);");
    expect(content).toContain("return DefaultArgsOps.configure(100, 10, 2.5, true);");
    expect(content).toContain('return ops.formatLabel("item", "-");');
    expect(content).toContain('return ops.formatLabel(null, "-");');
    expect(content).toContain('return DefaultArgsOps.describeTag("alpha", null);');
    expect(content).toContain("return DefaultArgsOps.openMode(1, Mode.Read);");
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

    // Kotlin receives native defaults for the sanctioned coalescing class.
    expect(content).toContain("class DefaultArgsOps(var familyNames: MutableList<String> = mutableListOf<String>())");
    expect(content).toContain("fun infinityDefault(value: Double = Double.POSITIVE_INFINITY): Double");
    expect(content).toContain("fun mapDefault(value: MutableMap<String, Int> = mutableMapOf()): MutableMap<String, Int>");
    expect(content).toContain("return DefaultArgsOps.infinityDefault()");
    expect(content).toContain("return DefaultArgsOps.mapDefault()");

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

    // Rust has no default syntax: omission is completed to None and each
    // entry point evaluates its sanctioned expression lazily.
    expect(content).toContain("pub fn new(family_names: Option<Vec<String>>) -> Self");
    expect(content).toContain("let family_names = family_names.unwrap_or_else(|| vec![]);");
    expect(content).toContain("pub fn infinity_default(value: Option<f64>) -> f64");
    expect(content).toContain("let value = value.unwrap_or_else(|| f64::INFINITY);");
    expect(content).toContain("pub fn map_default(value: Option<HashMap<String, u32>>) -> HashMap<String, u32>");
    expect(content).toContain("let value = value.unwrap_or_else(|| HashMap::new());");
    expect(content).toContain("return DefaultArgsOps::infinity_default(None);");
    expect(content).toContain("return DefaultArgsOps::map_default(None);");

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

  test("Swift generated tree keeps native coalescing defaults", () => {
    const swiftFile = path.join(swiftGenDir, "boring/DefaultArgsOps.swift");
    expect(fs.existsSync(swiftFile)).toBe(true);
    const content = fs.readFileSync(swiftFile, "utf8");

    expect(content).toContain("init(_ familyNames: [String] = [])");
    expect(content).toContain("static func infinityDefault(_ value: Double = Double.infinity) -> Double");
    expect(content).toContain("static func mapDefault(_ value: [String: Int32] = [:]) -> [String: Int32]");
    expect(content).toContain("return DefaultArgsOps.infinityDefault()");
    expect(content).toContain("return DefaultArgsOps.mapDefault()");
  });

  test("Dart generated tree normalizes coalescing defaults in the body", () => {
    const dartFile = path.join(dartGenDir, "lib/boring/default_args_ops.dart");
    expect(fs.existsSync(dartFile)).toBe(true);
    const content = fs.readFileSync(dartFile, "utf8");

    expect(content).toContain("DefaultArgsOps([List<String>? familyNames])");
    expect(content).toContain("this.familyNames = familyNames ?? <String>[];");
    expect(content).toContain("static double infinityDefault([double? value])");
    expect(content).toContain("final double normalized = value ?? double.infinity;");
    expect(content).toContain("static Map<String, int> mapDefault([Map<String, int>? value])");
    expect(content).toContain("final Map<String, int> normalized = value ?? <String, int>{};");
    expect(content).toContain("return DefaultArgsOps.infinityDefault()");
    expect(content).toContain("return DefaultArgsOps.mapDefault()");
  });
});
