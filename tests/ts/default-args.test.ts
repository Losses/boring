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
    expect(content).toContain("public static fieldAccessSample(items: string[], count: number = items.length): number");
    expect(content).toContain("public static localeSample(lang: string, fallback: string = (lang === \"en\" ? \"English\" : \"Other\")): string");
    expect(content).toContain("public static methodCallSample(text: string, normalized: string = text.toUpperCase()): string");
    expect(content).toContain("public static staticCallSample(value: number, clamped: number = DefaultArgsOps.clampBase(value)): number");
    expect(content).toContain("public static staticFieldSample(value: number, bound: number = StaticStateOps.limit): number");
    expect(content).toContain("public static binarySample(value: number, offset: number = value + 1): number");

    // A coalescing default reading an earlier coalescing parameter keeps
    // native defaults; omitting call sites stay omitted.
    expect(content).toContain("public static chainedCoalescing(fallback: number = 2.5, value: number = fallback): number");
    expect(content).toContain("export class ChainedPaint");
    expect(content).toContain("constructor(radius: number = 0.0, followRadius: number = radius)");
    expect(content).toContain("return DefaultArgsOps.chainedCoalescing();");

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

    // Parameter-reading coalescing defaults stay native on Kotlin.
    expect(content).toContain("fun greetWithPrefix(name: String, prefix: String = name): String");
    expect(content).toContain("fun fieldAccessSample(items: MutableList<String>, count: Int = items.size): Int");
    expect(content).toContain("fun localeSample(lang: String, fallback: String = if (lang == \"en\") \"English\" else \"Other\"): String");
    expect(content).toContain("fun methodCallSample(text: String, normalized: String = text.uppercase()): String");
    expect(content).toContain("fun staticCallSample(value: Int, clamped: Int = DefaultArgsOps.clampBase(value)): Int");
    expect(content).toContain("fun staticFieldSample(value: Int, bound: Int = StaticStateOps.limit): Int");
    expect(content).toContain("fun binarySample(value: Int, offset: Int = value + 1): Int");
    expect(content).toContain("fun dependenceEarlier(a: String, b: String = a): String");

    // A coalescing default reading an earlier coalescing parameter keeps
    // native defaults on the function and the primary constructor field.
    expect(content).toContain("fun chainedCoalescing(fallback: Double = 2.5, value: Double = fallback): Double");
    expect(content).toContain("class ChainedPaint(var radius: Double = 0.0, var followRadius: Double = radius)");

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

    // Rust normalizes parameter-reading defaults at entry in declaration order.
    expect(content).toContain("pub fn greet_with_prefix(name: &str, prefix: Option<String>) -> String");
    expect(content).toContain("let prefix = prefix.unwrap_or_else(|| name.to_string());");
    expect(content).toContain("pub fn field_access_sample(items: &mut [String], count: Option<u32>) -> u32");
    expect(content).toContain("let count = count.unwrap_or_else(|| match u32::try_from((items).len())");
    expect(content).toContain("let fallback = fallback.unwrap_or_else(|| if lang == \"en\".to_string() { \"English\".to_string() } else { \"Other\".to_string() });");
    expect(content).toContain("let normalized = normalized.unwrap_or_else(|| text.to_uppercase());");
    expect(content).toContain("let clamped = clamped.unwrap_or_else(|| DefaultArgsOps::clamp_base(value));");
    expect(content).toContain("pub fn static_field_sample(value: u32, bound: Option<u32>) -> u32");
    expect(content).toContain("let bound = bound.unwrap_or_else(|| StaticStateOps::limit);");
    expect(content).toContain("let offset = offset.unwrap_or_else(|| value + 1);");
    expect(content).toContain("let b = b.unwrap_or_else(|| a.to_string());");

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

    // A coalescing default reading an earlier coalescing parameter enters
    // after the earlier parameter's entry binding.
    expect(content).toContain("pub fn chained_coalescing(fallback: Option<f64>, value: Option<f64>) -> f64");
    expect(content).toContain("let fallback = fallback.unwrap_or_else(|| 2.5);");
    expect(content).toContain("let value = value.unwrap_or_else(|| fallback);");
    expect(content).toContain("let follow_radius = follow_radius.unwrap_or_else(|| radius);");
  });

  test("Swift generated tree lowers parameter-reading coalescing defaults in the body", () => {
    const swiftFile = path.join(swiftGenDir, "boring/DefaultArgsOps.swift");
    expect(fs.existsSync(swiftFile)).toBe(true);
    const content = fs.readFileSync(swiftFile, "utf8");

    expect(content).toContain("init(_ familyNames: [String] = [])");
    expect(content).toContain("static func infinityDefault(_ value: Double = Double.infinity) -> Double");
    expect(content).toContain("static func mapDefault(_ value: [String: Int32] = [:]) -> [String: Int32]");
    expect(content).toContain("return DefaultArgsOps.infinityDefault()");
    expect(content).toContain("return DefaultArgsOps.mapDefault()");
    expect(content).toContain("static func greetWithPrefix(_ name: String, _ prefix: String? = nil) -> String");
    expect(content).toContain("var prefix = prefix ?? name;");
    expect(content).toContain("static func fieldAccessSample(_ items: [String], _ count: Int32? = nil) -> Int32");
    expect(content).toContain("var count = count ?? Int32(items.count);");
    expect(content).toContain("static func localeSample(_ lang: String, _ fallback: String? = nil) -> String");
    expect(content).toContain("var fallback = fallback ?? (lang == \"en\" ? \"English\" : \"Other\");");
    expect(content).toContain("var normalized = normalized ?? text.uppercased();");
    expect(content).toContain("var clamped = clamped ?? DefaultArgsOps.clampBase(value);");
    expect(content).toContain("static func staticFieldSample(_ value: Int32, _ bound: Int32 = StaticStateOps.limit) -> Int32");
    expect(content).toContain("var offset = offset ?? value + 1;");
    expect(content).toContain("var b = b ?? a;");
    expect(content).toContain("static func chainedCoalescing(_ fallback: Double = 2.5, _ value: Double? = nil) -> Double");
    expect(content).toContain("var value = value ?? fallback;");
    expect(content).toContain("init(_ radius: Double = 0.0, _ followRadius: Double? = nil)");
    expect(content).toContain("var followRadius = followRadius ?? radius;");
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
    expect(content).toContain("static String greetWithPrefix(String name, [String? prefix])");
    expect(content).toContain("final String normalized = prefix ?? name;");
    expect(content).toContain("static int fieldAccessSample(List<String> items, [int? count])");
    expect(content).toContain("final int normalized = count ?? items.length;");
    expect(content).toContain("static String localeSample(String lang, [String? fallback])");
    expect(content).toContain("final String normalized = fallback ?? (lang == \"en\" ? \"English\" : \"Other\");");
    expect(content).toContain("final String value = normalized ?? text.toUpperCase();");
    expect(content).toContain("final int result = clamped ?? DefaultArgsOps.clampBase(value);");
    expect(content).toContain("static int staticFieldSample(int value, [int? bound])");
    expect(content).toContain("final int normalized = bound ?? static_state_ops.limit;");
    expect(content).toContain("final int result = offset ?? value + 1;");
    expect(content).toContain("final String normalized = b ?? a;");
    expect(content).toContain("final double resolvedValue = value ?? (fallback ?? 2.5);");
    expect(content).toContain("this.followRadius = followRadius ?? (radius ?? 0.0);");
  });
});
