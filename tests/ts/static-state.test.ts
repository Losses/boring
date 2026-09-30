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
		expect(content).toContain("private static var sections: TiqianArray<String> = TiqianArray<String>([])");
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
		const content = read("reference/rust/gen/boring/static_state_ops.rs");
		expect(content).toContain("pub static STATIC_STATE_OPS_CURRENT: Mutex<Option<UString>> = Mutex::new(None);");
		expect(content).toContain("static STATIC_STATE_OPS_SECTIONS: Mutex<Vec<UString>> = Mutex::new(vec![]);");;
		expect(content).toContain("pub const STATIC_STATE_OPS_LIMIT: u32 = 4096;");
		expect(content).toContain("STATIC_STATE_OPS_CURRENT.lock().unwrap_or_else(|e| e.into_inner())");;
		expect(content).toContain("*STATIC_STATE_OPS_CURRENT.lock().unwrap_or_else(|e| e.into_inner()) = Some(value.to_ustring());");;
		expect(content).toContain("STATIC_STATE_OPS_SECTIONS.lock().unwrap_or_else(|e| e.into_inner()).push(section.to_ustring());");;
		expect(content).not.toContain("unwrap()");
		expect(content).not.toContain("expect(");
		// The sanctioned &UStr constant lane builds its literal through pointer
		// casts (`as *const [u16] as *const ...UStr`); strip exactly that lane
		// so the no-cast guard still covers every other emitted construct.
		expect(content.replace(/as \*const \[u16\] as \*const [A-Za-z_:]+/g, "")).not.toContain(" as ");
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
	// One full haxe macro-compiler run measured at 29.5 s (baseline machine,
	// quiet window); 60_000 keeps ≥2× margin. The explicit timeout raises
	// only the harness patience for that subprocess, never the asserted
	// behavior.
}, 60_000);
