import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as path from "node:path";

const repoRoot = path.resolve(__dirname, "../..");
const read = (file: string): string => fs.readFileSync(path.join(repoRoot, file), "utf8");

describe("static fields generated trees", () => {
	test("TypeScript emits mutable, container, and constant static declarations", () => {
		const content = read("reference/ts/gen/boring/StaticStateOps.ts");
		expect(content).toContain("public static current: string | null = null;");
		expect(content).toContain("private static readonly sections: string[] = [];");
		expect(content).toContain("public static readonly limit: number = 4096;");
		expect(content).toContain("StaticStateOps.current = value;");
		expect(content).toContain("StaticStateOps.sections.push(section);");
	});

	test("Kotlin emits nullable var, mutableList val, and constant val", () => {
		const content = read("reference/kotlin/gen/boring/StaticStateOps.kt");
		expect(content).toContain("var current: String? = null");
		expect(content).toContain("private val sections: MutableList<String> = mutableListOf<String>()");
		expect(content).toContain("const val limit: Int = 4096");
		expect(content).toContain("StaticStateOps.current = value");
	});

	test("Swift keeps array statics mutable for value-semantic append", () => {
		const content = read("reference/swift/gen/boring/StaticStateOps.swift");
		expect(content).toContain("static var current: String? = nil");
		expect(content).toContain("private static var sections: [String] = []");
		expect(content).toContain("static let limit: Int32 = 4096");
		expect(content).toContain("StaticStateOps.current = value");
	});

	test("Dart flattens static state and applies the private underscore", () => {
		const content = read("reference/dart/gen/lib/boring/static_state_ops.dart");
		expect(content).toContain("String? current = null;");
		expect(content).toContain("final List<String> _sections = <String>[];");
		expect(content).toContain("final int limit = 4096;");
		expect(content).toContain("current = value;");
		expect(content).toContain("_sections.add(section);");
	});

	test("Rust uses Mutex guards and the direct constant lane", () => {
		const content = read("reference/rust-gen/src/boring/static_state_ops.rs");
		expect(content).toContain("pub static current: Mutex<Option<String>> = Mutex::new(None);");
		expect(content).toContain("static sections: Mutex<Vec<String>> = Mutex::new(vec![]);");
		expect(content).toContain("pub const limit: u32 = 4096;");
		expect(content).toContain("current.lock().unwrap_or_else(|e| e.into_inner())");
		expect(content).toContain("*current.lock().unwrap_or_else(|e| e.into_inner()) = Some(value.to_string());");
		expect(content).toContain("sections.lock().unwrap_or_else(|e| e.into_inner()).push(section.to_string());");
		expect(content).not.toContain("unwrap()");
		expect(content).not.toContain("expect(");
		expect(content).not.toContain(" as ");
	});
});

test("static initializer mutation is rejected with the sanctioned error", async () => {
	const proc = Bun.spawn(["haxe", "examples/ts.hxml", "tests.StaticStateInvalidProbe"], {
		cwd: repoRoot,
		stdout: "pipe",
		stderr: "pipe",
	});
	const [exitCode, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()]);
	expect(exitCode).not.toBe(0);
	expect(stderr).toContain("static field initializers accept null, literal, and empty array forms only");
});
