package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.BaseCompiler.BaseCompilerFileOutputType;
import reflaxe.PluginCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	reflaxe plugin producing the Rust lane of the translatable subset.

	Output layout is one file per Haxe module inside the package's
	directory, plus a `mod.rs` per package, plus a root `lib.rs` and
	runtime shims when referenced, all written through the framework's
	output manager so `-D rust-output=<dir>` controls placement.
**/
class Compiler extends PluginCompiler<Compiler> {
	/** Module path to declaration parts, in arrival order. */
	final parts: Map<String, Array<String>> = [];

	/** Module path to emission context. */
	final contexts: Map<String, RustDecl> = [];

	final state: RustEmissionState;

	var current: Null<RustDecl> = null;

	public static function use() {
		final compiler = new Compiler();
		haxe.macro.Context.onAfterTyping(compiler.preScan);
		ReflectCompiler.AddCompiler(compiler, {
			fileOutputType: BaseCompilerFileOutputType.Manual,
			fileOutputExtension: ".rs",
			outputDirDefineName: "rust-output",
			unwrapTypedefs: false,
			normalizeEIE: false,
			preventRepeatVars: false,
			ignoreExterns: true,
		});
	}

	public function new() {
		super();
		state = new RustEmissionState();
	}

	// ------------------------------------------------------------------
	// Declarations
	// ------------------------------------------------------------------

	public function compileClassImpl(classType: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Null<String> {
		// Resident runtime modules live under src/, outside the
		// intercepted source roots, and still compile: each lane lists
		// them in its hxml so typing reaches them (RuntimeResidents).
		final isResident = RuntimeResidents.isResident(classType.module);
		if(classType.isExtern || isSyntheticImpl(classType.name) || isInlineOnly(classType, varFields, funcFields) || (!isResident && !inSourceScope(classType.pos))) {
			return null;
		}

		var hasTestMethods = false;
		for(f in funcFields) {
			if(f.field.meta.has(":test")) {
				hasTestMethods = true;
				break;
			}
		}

		if(hasTestMethods) {
			final sortedFuncs = funcFields.copy();
			sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));

			for(f in sortedFuncs) {
				if(!f.field.meta.has(":test")) continue;
				final id = classType.module + "." + f.field.name;
				if(!f.field.isPublic) {
					Context.error("Test function " + id + " must be public", f.field.pos);
				}
				if(!f.isStatic) {
					Context.error("Test function " + id + " must be static", f.field.pos);
				}
				if(f.args.length != 0) {
					Context.error("Test function " + id + " must take no arguments and return Void", f.field.pos);
				}
				final isVoid = switch(Context.follow(f.ret)) {
					case TAbstract(a, _): a.get().name == "Void";
					case _: false;
				};
				if(!isVoid) {
					Context.error("Test function " + id + " must take no arguments and return Void", f.field.pos);
				}
			}
			state.testModules.set(classType.module, true);
		}

		final decl = contextFor(classType.module);
		final result = decl.classDecl(classType, varFields, funcFields);
		if(result != null && result.length > 0) {
			parts.get(classType.module).push(result);
		}
		return result;
	}

	public function compileEnumImpl(enumType: EnumType, options: Array<EnumOptionData>): Null<String> {
		if(!inSourceScope(enumType.pos)) {
			return null;
		}
		if(state.payloadEnumOwners.exists(enumType.module)) {
			return null;
		}
		final decl = contextFor(enumType.module);
		final result = decl.enumDecl(enumType, options);
		if(result != null && result.length > 0) {
			parts.get(enumType.module).push(result);
		}
		return result;
	}

	public override function compileTypedef(def: DefType): Null<String> {
		if(!inSourceScope(def.pos)) {
			return null;
		}
		final decl = contextFor(def.module);
		final result = decl.typedefDecl(def);
		if(result != null && result.length > 0) {
			parts.get(def.module).push(result);
		}
		return result;
	}

	public function compileExpressionImpl(e: TypedExpr, topLevel: Bool): Null<String> {
		final decl = current != null ? current : new RustDecl("eval", state);
		return topLevel ? decl.topLevelStatements(e) : decl.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Output
	// ------------------------------------------------------------------

	public override function generateFilesManually() {
		final modules = [];
		for(module in parts.keys()) modules.push(module);
		modules.sort(Reflect.compare);

		final packages: Map<String, Array<String>> = [];

		for(module in modules) {
			if(state.payloadEnumModules.exists(module)) {
				continue;
			}
			if(RuntimeResidents.isResident(module)) {
				emitResidentModule(module, contexts.get(module));
				continue;
			}
			final decl = contexts.get(module);
			final imports = decl.renderImports();
			final body = parts.get(module).join("\n\n");
			final isTest = state.testModules.exists(module);
			final content = (isTest ? "#![cfg(test)]\n\n" : "")
				+ imports
				+ (imports.length > 0 ? "\n" : "")
				+ body
				+ "\n";
			saveTreeFile(modulePath(module), content);

			final pack = packageOf(module);
			if(!packages.exists(pack)) {
				packages.set(pack, []);
			}
			final modName = moduleLeafName(module);
			packages.get(pack).push(modName);
		}

		// Generate package mod.rs files
		for(pack in packages.keys()) {
			if(pack == "tests") {
				continue;
			}
			final modNames = packages.get(pack);
			modNames.sort(Reflect.compare);
			final lines = ["#![allow(ambiguous_glob_reexports)]", ""];
			for(m in modNames) {
				lines.push("pub mod " + m + ";");
			}
			lines.push("");
			for(m in modNames) {
				lines.push("pub use " + m + "::*;");
			}
			final modPath = pack == "" ? "mod.rs" : pack.split(".").map(RustImports.toSnakeCase).join("/") + "/mod.rs";
			saveTreeFile(modPath, lines.join("\n") + "\n");
		}

		if(packages.exists("tests")) {
			generateTestHelper();
			final modNames = packages.get("tests");
			if(modNames.indexOf("test_helper") < 0) {
				modNames.push("test_helper");
			}
			modNames.sort(Reflect.compare);
			final lines = ["#![allow(unused_imports)]", ""];
			for(m in modNames) {
				lines.push("pub mod " + m + ";");
			}
			lines.push("");
			for(m in modNames) {
				lines.push("pub use " + m + "::*;");
			}
			saveTreeFile("tests/mod.rs", lines.join("\n") + "\n");
		}

		// Emit runtime shims
		emitShim("haxe.io.FPHelper", "fp_helper.rs", RustRuntime.FP_HELPER_SOURCE);
		emitShim("haxe.io.BytesBuffer", "bytes_buffer.rs", RustRuntime.BYTES_BUFFER_SOURCE);
		emitShim("std.Console", "console.rs", RustRuntime.CONSOLE_SOURCE);
		emitShim("std.Process", "process.rs", RustRuntime.PROCESS_SOURCE);
		emitShim("std.Test", "test.rs", RustRuntime.TEST_SOURCE);

		final emitDir = RuntimeConfig.emitDir();
		if(emitDir != null && hasAnyShim()) {
			final runtimeMods = [];
			if(state.shimsUsed.exists("haxe.io.FPHelper")) runtimeMods.push("fp_helper");
			if(state.shimsUsed.exists("haxe.io.BytesBuffer")) runtimeMods.push("bytes_buffer");
			if(state.shimsUsed.exists("std.Console")) runtimeMods.push("console");
			if(state.shimsUsed.exists("std.Process")) runtimeMods.push("process");
			if(state.shimsUsed.exists("std.Test")) {
				runtimeMods.push("test");
				runtimeMods.push("test_core");
			}
			if(state.shimsUsed.exists("std.UStringRT")) runtimeMods.push("u_string");
			if(state.shimsUsed.exists("std.Graphemes")) {
				runtimeMods.push("graphemes");
				runtimeMods.push("grapheme_walk");
			}
			// The sorted externs all front runtime.SortedTable, which
			// emitResidentModule writes as sorted_table.rs.
			final sortedUsed = RuntimeResidents.externsOf("runtime.SortedTable").filter(m -> state.shimsUsed.exists(m));
			if(sortedUsed.length > 0) runtimeMods.push("sorted_table");
			runtimeMods.sort(Reflect.compare);
			final rtLines = [];
			for(m in runtimeMods) rtLines.push("pub mod " + m + ";");
			// No glob re-exports: generated code references every runtime
			// declaration by its qualified path, and re-exporting two
			// modules that share a function name (ustring and graphemes
			// both define count, at, slice) is an ambiguous re-export.
			saveTreeFile(RuntimeConfig.emitPath(emitDir, "mod.rs"), rtLines.join("\n") + "\n");
		}

		// Generate root lib.rs
		final libLines = [];
		final sortedPacks = [for(p in packages.keys()) p];
		sortedPacks.sort(Reflect.compare);
		for(p in sortedPacks) {
			if(p != "" && p != "tests") {
				final sname = RustImports.toSnakeCase(p);
				libLines.push("pub mod " + sname + ";");
			}
		}
		if(emitDir != null && hasAnyShim()) {
			libLines.push("pub mod " + emitDir + ";");
		}
		if(packages.exists("tests")) {
			libLines.push("#[cfg(test)]");
			libLines.push("pub mod tests;");
		}
		libLines.push("");
		for(p in sortedPacks) {
			if(p != "" && p != "tests") {
				final sname = RustImports.toSnakeCase(p);
				libLines.push("pub use " + sname + "::*;");
			}
		}
		saveTreeFile("lib.rs", libLines.join("\n") + "\n");

		if(PackageShell.enabled()) {
			saveTreeFile("Cargo.toml", packageManifest());
		}
		if(PackageArtifacts.enabled()) {
			PackageArtifacts.requireShell();
			PackageArtifacts.emitTarGz(Context.definedValue("rust-output"), false, ".crate");
		}
	}

	/**
		Saves one file through the output manager and records the write
		for artifact packing (feature spec 25).
	**/
	function saveTreeFile(path: String, content: String): Void {
		output.saveFile(path, content);
		PackageArtifacts.record(path, content);
	}

	/**
		The crate manifest of the generated tree (feature spec 24). The
		crate is the output directory itself: the library entry is the
		compiler's own lib.rs, the dependency set is empty because the
		translatable subset references no external crate, and one
		`package-test` define appends the integration-test block
		repositories with tests outside the crate need. The generated
		`tests/` directory is a `#[cfg(test)]` module tree of the lib,
		not cargo integration tests, so test autodiscovery is off.
	**/
	function packageManifest(): String {
		final license = PackageShell.license();
		final lines = [
			"# Generated by the reflaxe Rust target. Do not edit.",
			"[package]",
			'name = "${PackageShell.name()}"',
			'version = "${PackageShell.version()}"',
		];
		if(license != null) {
			lines.push('license = "$license"');
		}
		lines.push('edition = "2024"');
		lines.push('autotests = false');
		lines.push("");
		lines.push("[lib]");
		lines.push('path = "lib.rs"');
		final test = PackageShell.rustTest();
		if(test != null) {
			lines.push("");
			lines.push("[[test]]");
			lines.push('name = "${test.name}"');
			lines.push('path = "${test.path}"');
		}
		return lines.join("\n") + "\n";
	}

	function generateTestHelper(): Void {
		// The float helpers follow the precision switch so the aggregate
		// helpers (equals_vec_f32, ...) resolve against a defined symbol
		// on both lanes (feature spec 23, ruling 10).
		final real = FloatPrecision.isF32() ? "f32" : "f64";
		final lines = [
			"// Generated test helper for type-guided assertions (Ruling C);
			// the canonical failure text and scalar formatting live in the
			// resident runtime.TestCore.",
			"#![allow(unused_imports, dead_code)]",
			"",
			"use crate::runtime::test_core;",
			"",
			"pub fn equals_bytes(a: &[u8], b: &[u8]) -> bool { a == b }",
			"pub fn format_bytes(v: &[u8]) -> String { test_core::TestCore::format_bytes(v) }",
			"pub fn assert_equals_bytes(expected: &[u8], actual: &[u8], message: &str) {",
			"    if !equals_bytes(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_bytes(expected), &format_bytes(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_bool(a: &bool, b: &bool) -> bool { *a == *b }",
			"pub fn format_bool(v: &bool) -> String { if *v { \"true\".to_string() } else { \"false\".to_string() } }",
			"pub fn assert_equals_bool(expected: &bool, actual: &bool, message: &str) {",
			"    if !equals_bool(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_bool(expected), &format_bool(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_i32(a: &i32, b: &i32) -> bool { *a == *b }",
			"pub fn format_i32(v: &i32) -> String { v.to_string() }",
			"pub fn assert_equals_i32(expected: &i32, actual: &i32, message: &str) {",
			"    if !equals_i32(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_i32(expected), &format_i32(actual));",
			"    }",
			"}",
			"",
			'pub fn equals_$real(a: &$real, b: &$real) -> bool { *a == *b }',
			'pub fn format_$real(v: &$real) -> String { test_core::TestCore::format_float(*v) }',
			'pub fn assert_equals_$real(expected: &$real, actual: &$real, message: &str) {',
			'    if !equals_$real(expected, actual) {',
			'        test_core::TestCore::report_failure(message, &format_$real(expected), &format_$real(actual));',
			"    }",
			"}",
			"",
			"pub fn equals_u32(a: &u32, b: &u32) -> bool { *a == *b }",
			"pub fn format_u32(v: &u32) -> String { v.to_string() }",
			"pub fn assert_equals_u32(expected: &u32, actual: &u32, message: &str) {",
			"    if !equals_u32(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_u32(expected), &format_u32(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_u16(a: &u16, b: &u16) -> bool { *a == *b }",
			"pub fn format_u16(v: &u16) -> String { v.to_string() }",
			"pub fn assert_equals_u16(expected: &u16, actual: &u16, message: &str) {",
			"    if !equals_u16(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_u16(expected), &format_u16(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_usize(a: &usize, b: &usize) -> bool { *a == *b }",
			"pub fn format_usize(v: &usize) -> String { v.to_string() }",
			"pub fn assert_equals_usize(expected: &usize, actual: &usize, message: &str) {",
			"    if !equals_usize(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_usize(expected), &format_usize(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_string(a: &String, b: &String) -> bool { a == b }",
			"pub fn format_string(v: &String) -> String { test_core::TestCore::format_string(v) }",
			"pub fn assert_equals_string(expected: &String, actual: &String, message: &str) {",
			"    if !equals_string(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_string(expected), &format_string(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_opt_string(a: &Option<String>, b: &Option<String>) -> bool { a == b }",
			"pub fn format_opt_string(v: &Option<String>) -> String { match v { Some(s) => test_core::TestCore::format_string(s), None => \"null\".to_string() } }",
			"pub fn assert_equals_opt_string(expected: &Option<String>, actual: &Option<String>, message: &str) {",
			"    if !equals_opt_string(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_opt_string(expected), &format_opt_string(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_opt_u32(a: &Option<u32>, b: &Option<u32>) -> bool { a == b }",
			"pub fn format_opt_u32(v: &Option<u32>) -> String { match v { Some(x) => x.to_string(), None => \"null\".to_string() } }",
			"pub fn assert_equals_opt_u32(expected: &Option<u32>, actual: &Option<u32>, message: &str) {",
			"    if !equals_opt_u32(expected, actual) {",
			"        test_core::TestCore::report_failure(message, &format_opt_u32(expected), &format_opt_u32(actual));",
			"    }",
			"}"
		];

		final dummyImports = new RustImports("tests", state);
		final types = new RustType(dummyImports, state);

		final sortedKeys = [for(k in state.testReachableTypes.keys()) k];
		sortedKeys.sort(Reflect.compare);

		for(k in sortedKeys) {
			final t = state.testReachableTypes.get(k);
			switch(t) {
				case TInst(c, params) if(c.get().name == "Array"):
					final elemType = params[0];
					final elemTypeStr = rustType(elemType);
					final safeSnake = typeSafeSnake(elemType, types);
					lines.push("");
					lines.push('pub fn equals_vec_$safeSnake(a: &[$elemTypeStr], b: &[$elemTypeStr]) -> bool {');
					lines.push('    if a.len() != b.len() { return false; }');
					lines.push('    for i in 0..a.len() { if !equals_$safeSnake(&a[i], &b[i]) { return false; } }');
					lines.push('    true');
					lines.push('}');
					lines.push('pub fn format_vec_$safeSnake(v: &[$elemTypeStr]) -> String {');
					lines.push('    let mut parts: Vec<String> = Vec::new();');
					lines.push('    for item in v { parts.push(format_$safeSnake(item)); }');
					lines.push('    format!("[{}]", parts.join(", "))');
					lines.push('}');
					lines.push('pub fn assert_equals_vec_$safeSnake(expected: &[$elemTypeStr], actual: &[$elemTypeStr], message: &str) {');
					lines.push('    if !equals_vec_$safeSnake(expected, actual) {');
					lines.push('        test_core::TestCore::report_failure(message, &format_vec_$safeSnake(expected), &format_vec_$safeSnake(actual));');
					lines.push('    }');
					lines.push('}');
				case TAbstract(a, params) if(a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
					final elemType = params[0];
					final elemTypeStr = rustType(elemType);
					final safeSnake = typeSafeSnake(elemType, types);
					lines.push("");
					lines.push('pub fn equals_vec_$safeSnake(a: &[$elemTypeStr], b: &[$elemTypeStr]) -> bool {');
					lines.push('    if a.len() != b.len() { return false; }');
					lines.push('    for i in 0..a.len() { if !equals_$safeSnake(&a[i], &b[i]) { return false; } }');
					lines.push('    true');
					lines.push('}');
					lines.push('pub fn format_vec_$safeSnake(v: &[$elemTypeStr]) -> String {');
					lines.push('    let mut parts: Vec<String> = Vec::new();');
					lines.push('    for item in v { parts.push(format_$safeSnake(item)); }');
					lines.push('    format!("[{}]", parts.join(", "))');
					lines.push('}');
					lines.push('pub fn assert_equals_vec_$safeSnake(expected: &[$elemTypeStr], actual: &[$elemTypeStr], message: &str) {');
					lines.push('    if !equals_vec_$safeSnake(expected, actual) {');
					lines.push('        test_core::TestCore::report_failure(message, &format_vec_$safeSnake(expected), &format_vec_$safeSnake(actual));');
					lines.push('    }');
					lines.push('}');
				case TType(def, _):
					final d = def.get();
					switch(d.type) {
						case TAnonymous(anonRef):
							final structPath = "crate::" + RustImports.moduleToRustPath(d.module) + "::" + d.name;
							final safeSnake = RustImports.toSnakeCase(d.name);
							final fields = anonRef.get().fields.copy();
							fields.sort((x, y) -> Reflect.compare(Context.getPosInfos(x.pos).min, Context.getPosInfos(y.pos).min));
							final eqChecks = [for(f in fields) 'equals_' + typeSafeSnake(f.type, types) + '(&a.' + RustImports.toSnakeCase(f.name) + ', &b.' + RustImports.toSnakeCase(f.name) + ')'].join(" && ");
							final fmtParts = [for(f in fields) '"' + f.name + ': ".to_string() + &format_' + typeSafeSnake(f.type, types) + '(&v.' + RustImports.toSnakeCase(f.name) + ')'].join(', ');
							lines.push("");
							lines.push('pub fn equals_$safeSnake(a: &$structPath, b: &$structPath) -> bool {');
							lines.push('    ' + (eqChecks.length > 0 ? eqChecks : "true"));
							lines.push('}');
							lines.push('pub fn format_$safeSnake(v: &$structPath) -> String {');
							lines.push('    format!("{{{}}}", [' + fmtParts + '].join(", "))');
							lines.push('}');
							lines.push('pub fn assert_equals_$safeSnake(expected: &$structPath, actual: &$structPath, message: &str) {');
							lines.push('    if !equals_$safeSnake(expected, actual) {');
							lines.push('        test_core::TestCore::report_failure(message, &format_$safeSnake(expected), &format_$safeSnake(actual));');
							lines.push('    }');
							lines.push('}');
						case _:
					}
				case TEnum(e, _):
					final en = e.get();
					final ownerModule = state.payloadEnumModules.get(en.module);
					final targetModule = ownerModule != null ? ownerModule : en.module;
					final enumPath = "crate::" + RustImports.moduleToRustPath(targetModule) + "::" + en.name;
					final safeSnake = RustImports.toSnakeCase(en.name);
					lines.push("");
					lines.push('pub fn equals_$safeSnake(a: &$enumPath, b: &$enumPath) -> bool { a == b }');
					final arms = [];
					for(opt in en.constructs) {
						switch(Context.follow(opt.type)) {
							case TFun(args, _):
								final patArgs = [for(arg in args) RustImports.toSnakeCase(arg.name)].join(", ");
								final fmtArgs = [for(arg in args) {
									final argType = (arg.name == "offset" || arg.name == "length" || arg.name == "remaining") ? "usize" : typeSafeSnake(arg.t, types);
									'format_' + argType + '(' + RustImports.toSnakeCase(arg.name) + ')';
								}].join(' + ", " + ');
								arms.push('        $enumPath::${opt.name} { $patArgs } => format!("${opt.name}({})", $fmtArgs),');
							case _:
								arms.push('        $enumPath::${opt.name} => "${opt.name}".to_string(),');
						}
					}
					lines.push('pub fn format_$safeSnake(v: &$enumPath) -> String {');
					lines.push('    match v {');
					for(a in arms) lines.push(a);
					lines.push('    }');
					lines.push('}');
					lines.push('pub fn assert_equals_$safeSnake(expected: &$enumPath, actual: &$enumPath, message: &str) {');
					lines.push('    if !equals_$safeSnake(expected, actual) {');
					lines.push('        test_core::TestCore::report_failure(message, &format_$safeSnake(expected), &format_$safeSnake(actual));');
					lines.push('    }');
					lines.push('}');
				case _:
			}
		}
		saveTreeFile("tests/test_helper.rs", lines.join("\n") + "\n");
	}

	function rustType(t: Type): String {
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				switch(abs.pack.concat([abs.name]).join(".")) {
					case "Int": "u32";
					case "Float": FloatPrecision.isF32() ? "f32" : "f64";
					case "Bool": "bool";
					case "String": "String";
					case "std.ReadOnlyArray": "Vec<" + rustType(params[0]) + ">";
					case _: abs.name;
				}
			case TInst(c, params):
				final cls = c.get();
				if(cls.name == "String") "String";
				else if(cls.name == "Array") "Vec<" + rustType(params[0]) + ">";
				else if(cls.name == "Bytes" || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) "Vec<u8>";
				else "crate::" + RustImports.moduleToRustPath(cls.module) + "::" + cls.name;
			case TType(def, params):
				final d = def.get();
				"crate::" + RustImports.moduleToRustPath(d.module) + "::" + d.name;
			case TEnum(e, params):
				final en = e.get();
				final ownerModule = state.payloadEnumOwners.get(en.module);
				final targetModule = ownerModule != null ? ownerModule : en.module;
				"crate::" + RustImports.moduleToRustPath(targetModule) + "::" + en.name;
			case _: "()";
		};
	}

	function typeSafeSnake(t: Type, ?types: RustType): String {
		if(types != null) {
			final s = types.of(t);
			if(s == "u32" || s == "u16" || s == "usize" || s == "i32" || s == "i64" || s == "f32" || s == "f64" || s == "bool") {
				return s;
			}
			if(s == "String") return "string";
			if(s == "Vec<u8>") return "bytes";
		}
		return switch(t) {
			case TAbstract(a, _):
				switch(a.get().name) {
					case "Int": "i32";
					case "Float": FloatPrecision.isF32() ? "f32" : "f64";
					case "Bool": "bool";
					case "String": "string";
					case _: RustImports.toSnakeCase(a.get().name);
				}
			case TInst(c, _):
				switch(c.get().name) {
					case "String": "string";
					case "Bytes": "bytes";
					case _: RustImports.toSnakeCase(c.get().name);
				}
			case TType(def, _): RustImports.toSnakeCase(def.get().name);
			case TEnum(e, _): RustImports.toSnakeCase(e.get().name);
			case _: "unknown";
		};
	}

	function hasAnyShim(): Bool {
		for(_ in state.shimsUsed.keys()) return true;
		return false;
	}

	function emitShim(module: String, fileName: String, source: String): Void {
		if(!state.shimsUsed.exists(module)) {
			return;
		}
		final dir = RuntimeConfig.emitDir();
		if(dir == null) {
			return;
		}
		final path = RuntimeConfig.emitPath(dir, fileName);
		saveTreeFile(path, StringTools.trim(source) + "\n");
	}

	/**
		Writes one resident runtime module into the runtime-emit
		directory. The
		module compiled through the normal typed pipeline like a business
		module; its output lands beside the runtime shims instead of the
		business tree. The extern that fronts the resident set gates the
		emission the way shim usage gates the shims, so an unreferenced
		runtime stays out of the output.
	**/
	function emitResidentModule(module: String, decl: Null<RustDecl>): Void {
		var externUsed = false;
		for(externModule in RuntimeResidents.externsOf(module)) {
			if(state.shimsUsed.exists(externModule)) {
				externUsed = true;
				break;
			}
		}
		if(!externUsed) {
			return;
		}
		final dir = RuntimeConfig.emitDir();
		if(decl == null || dir == null) {
			return;
		}
		final moduleParts = parts.get(module);
		if(moduleParts == null || moduleParts.length == 0) {
			return;
		}
		final imports = decl.renderImports();
		final body = moduleParts.join("\n\n");
		final fileName = RustImports.toSnakeCase(moduleLeafName(module)) + ".rs";
		// runtime.UString carries the business ABI adapters beside the
		// compiled class: business callers reach the u32 free functions,
		// resident callers reach the class itself, and one file holds the
		// whole UString runtime.
		final abiSource = module == "runtime.UString" ? "\n" + StringTools.trim(RustRuntime.USTRING_ABI_SOURCE) + "\n" : "";
		final content = imports + (imports.length > 0 ? "\n" : "") + body + abiSource + "\n";
		saveTreeFile(RuntimeConfig.emitPath(dir, fileName), content);
	}

	// ------------------------------------------------------------------
	// Internals
	// ------------------------------------------------------------------

	function preScan(mtypes: Array<haxe.macro.Type.ModuleType>): Void {
		for(mt in mtypes) {
			switch(mt) {
				case TClassDecl(c):
					final cls = c.get();
					if(cls.isExtern || isSyntheticImpl(cls.name) || !inSourceScope(cls.pos)) {
						continue;
					}
					if(RustDecl.isExceptionSubclass(cls)) {
						final ctor = cls.constructor != null ? cls.constructor.get() : null;
						if(ctor != null) {
							switch(ctor.type) {
								case TFun(args, _):
									for(a in args) {
										switch(a.t) {
											case TEnum(e, _):
												final payload = e.get();
												state.payloadEnumModules.set(payload.module, cls.module);
												state.payloadEnumOwners.set(payload.module, cls.name);
												state.exceptionPayloads.set(cls.module, payload.module);
											case _:
										}
									}
								case _:
							}
						}
					}
				case TEnumDecl(e):
					final en = e.get();
					if(!inSourceScope(en.pos)) {
						continue;
					}
					for(o in en.constructs) {
						switch(Context.follow(o.type)) {
							case TFun(args, _):
								if(args.length == 1 && args[0].name == "remaining") {
									state.errorModule = en.module;
									state.errorName = en.name;
								}
							case _:
								if(o.name == "CountOverflow") {
									state.overflowVariant = o.name;
									state.countOverflowEnums.set(en.module, true);
								}
						}
					}
				case TTypeDecl(def):
					final d = def.get();
					if(!inSourceScope(d.pos)) {
						continue;
					}
					switch(d.type) {
						case TAnonymous(anon):
							final sig = RustDecl.structureSignature(anon);
							final existing = state.structTypedefs.get(sig);
							if(existing != null && (existing.name != d.name || existing.module != d.module)) {
								Context.error("typedefs " + existing.name + " and " + d.name + " share one anonymous structure shape", d.pos);
							}
							state.structTypedefs.set(sig, {module: d.module, name: d.name});
						case _:
					}
				case _:
			}
		}
		scanFallibility(mtypes);
	}

	/**
		Computes the fallibility of every function in source scope. Direct
		throws and runtime-shim calls make a function fallible, and the
		property then spreads to callers through call edges until nothing
		changes. Each fallible function carries the error enum it can
		produce, so Result-returning callers lower with the right error
		type instead of a global assumption.
	**/
	function scanFallibility(mtypes: Array<haxe.macro.Type.ModuleType>): Void {
		final fallible = new Map<String, Bool>();
		final enumOf = new Map<String, {module: String, name: String}>();
		final conflicts = new Map<String, Bool>();
		// An edge records the error enums its call site sits inside a try
		// region for: a fully handled domain does not infect the enclosing
		// function (features/06 catch-site lowering).
		final entries: Array<{key: String, edges: Array<{callee: String, absorbed: Array<String>}>}> = [];
		function mergeEnum(key: String, pair: {module: String, name: String}): Bool {
			final existing = enumOf.get(key);
			if(existing == null) {
				enumOf.set(key, pair);
				return true;
			}
			if(existing.module != pair.module) {
				conflicts.set(key, true);
			}
			return false;
		}
		// A u32 length write lowers through u32::try_from(...)?, so its
		// overflow belongs to the same error enum the runtime shims use.
		function markFallibleThroughLength(key: String): Void {
			fallible.set(key, true);
			if(state.errorModule != null && state.errorName != null) {
				mergeEnum(key, {module: state.errorModule, name: state.errorName});
			}
		}
		for(mt in mtypes) {
			switch(mt) {
				case TClassDecl(c):
					final cls = c.get();
					if(cls.isExtern || isSyntheticImpl(cls.name) || !inSourceScope(cls.pos)) {
						continue;
					}
					function scanField(field: haxe.macro.Type.ClassField, isStatic: Bool) {
						switch(field.type) {
							case TFun(_, _):
								final body = field.expr();
								if(body == null) return;
								final key = RustEmissionState.funcKey(cls.module, field.name, isStatic);
								final entry = {key: key, edges: new Array<{callee: String, absorbed: Array<String>}>()};
								function walk(e: TypedExpr, absorbed: Array<String>) {
									function descend() {
										haxe.macro.TypedExprTools.iter(e, function(child) walk(child, absorbed));
									}
									switch(e.expr) {
										case TThrow(t):
											final pair = thrownPayloadEnum(stripDecorations(t));
											if(pair != null && absorbed.indexOf(pair.module) >= 0) {
												// The region's clauses catch this domain.
											} else {
												fallible.set(key, true);
												if(pair != null) {
													mergeEnum(key, pair);
												}
											}
											descend();
										case TCall(fn, callArgs):
											switch(fn.expr) {
												case TField(_, FInstance(cc, _, cf)):
													final calleeName = cf.get().name;
													if(isStringBufFaultOp(cc.get().module, calleeName)) {
														// stdlib/08: the buffer checks end the owner
														// through Err, in std.UStringFault.
														final payload = state.exceptionPayloads.get("std.UStringException");
														final faultModule = payload != null ? payload : "std.UStringFault";
														if(absorbed.indexOf(faultModule) < 0) {
															fallible.set(key, true);
															mergeEnum(key, {module: faultModule, name: faultModule.split(".").pop()});
														}
													}
													if(RustEmissionState.runtimeShimIsFallible(calleeName)) {
														if(!(state.errorModule != null && absorbed.indexOf(state.errorModule) >= 0)) {
															fallible.set(key, true);
															if(state.errorModule != null && state.errorName != null) {
																mergeEnum(key, {module: state.errorModule, name: state.errorName});
															}
														}
													} else {
														if(isLengthConversion(calleeName, callArgs) && !(state.errorModule != null && absorbed.indexOf(state.errorModule) >= 0)) {
															markFallibleThroughLength(key);
														}
														entry.edges.push({callee: RustEmissionState.funcKey(cc.get().module, calleeName, false), absorbed: absorbed.slice(0, absorbed.length)});
													}
												case TField(_, FStatic(cc, cf)):
													final calleeName = cf.get().name;
													if(RustEmissionState.runtimeShimIsFallible(calleeName)) {
														if(!(state.errorModule != null && absorbed.indexOf(state.errorModule) >= 0)) {
															fallible.set(key, true);
															if(state.errorModule != null && state.errorName != null) {
																mergeEnum(key, {module: state.errorModule, name: state.errorName});
															}
														}
													} else {
														if(isLengthConversion(calleeName, callArgs) && !(state.errorModule != null && absorbed.indexOf(state.errorModule) >= 0)) {
															markFallibleThroughLength(key);
														}
														entry.edges.push({callee: RustEmissionState.funcKey(cc.get().module, calleeName, true), absorbed: absorbed.slice(0, absorbed.length)});
													}
												case _:
											}
											descend();
										case TTry(regionBody, regionCatches):
											// The caught domain vanishes inside the
											// region body; the handler expressions
											// keep every edge they carry.
											final caughtModules = [for(c in regionCatches) caughtPayloadEnumModuleOf(c.v)];
											final absorbedBody = absorbed.concat([for(m in caughtModules) if(m != null) m]);
											walk(regionBody, absorbedBody);
											for(c in regionCatches) {
												walk(c.expr, absorbed);
											}
										case _:
											descend();
									}
								}
								walk(body, []);
								entries.push(entry);
							case _:
						}
					}
					for(field in cls.statics.get()) scanField(field, true);
					for(field in cls.fields.get()) scanField(field, false);
				case _:
			}
		}
		var changed = true;
		while(changed) {
			changed = false;
			for(entry in entries) {
				for(edge in entry.edges) {
					final edgeEnum = enumOf.get(edge.callee);
					if(edgeEnum == null) continue;
					if(edge.absorbed.indexOf(edgeEnum.module) >= 0) continue;
					if(mergeEnum(entry.key, edgeEnum)) changed = true;
					if(!fallible.exists(entry.key)) {
						fallible.set(entry.key, true);
						changed = true;
					}
				}
			}
		}
		for(key in fallible.keys()) {
			final pair = enumOf.get(key);
			if(pair != null) {
				state.funcErrorEnums.set(key, pair);
			}
		}
		for(key in conflicts.keys()) {
			state.funcEnumConflicts.set(key, true);
		}
	}

	/**
		stdlib/08: add, addChar, and toString on std.StringBuf carry the
		unpaired-surrogate check, so a call makes its owner fallible in
		std.UStringFault like a std.UString construction check.
	**/
	function isStringBufFaultOp(module: String, calleeName: String): Bool {
		if(module != "std.StringBuf" && module != "StringBuf") {
			return false;
		}
		return calleeName == "add" || calleeName == "addChar" || calleeName == "toString";
	}

	function stripDecorations(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripDecorations(inner);
			case _: e;
		}
	}

	/**
		Recognizes writeU32(x.length): the Rust lowering narrows the count
		through u32::try_from(x)?, so the call makes its owner fallible
		regardless of the Haxe signature.
	**/
	function isLengthConversion(calleeName: String, args: Array<TypedExpr>): Bool {
		if(calleeName != "writeU32" || args.length != 1) {
			return false;
		}
		return switch(stripDecorations(args[0]).expr) {
			case TField(_, fa):
				switch(fa) {
					case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf) | FClosure(_, cf): cf.get().name == "length";
					case FEnum(_, ef): ef.name == "length";
					case FDynamic(n): n == "length";
				}
			case _: false;
		}
	}

	/**
		Returns the payload enum module a catch clause handles: the caught
		variable's class maps through exceptionPayloads, and a class without
		a payload enum has no absorbable domain.
	**/
	function caughtPayloadEnumModuleOf(v: haxe.macro.Type.TVar): Null<String> {
		return switch(v.t) {
			case TInst(c, _):
				state.exceptionPayloads.exists(c.get().module) ? state.exceptionPayloads.get(c.get().module) : null;
			case _: null;
		}
	}

	function thrownPayloadEnum(thrown: TypedExpr): Null<{module: String, name: String}> {
		return switch(thrown.expr) {
			case TNew(c, _, args) if(args.length > 0 && state.exceptionPayloads.exists(c.get().module)):
				switch(stripDecorations(args[0]).expr) {
					case TField(_, FEnum(en, _)):
						{module: en.get().module, name: en.get().name};
					case TCall(fn, _):
						switch(stripDecorations(fn).expr) {
							case TField(_, FEnum(en, _)):
								{module: en.get().module, name: en.get().name};
							case _: null;
						}
					case _: null;
				}
			case _: null;
		}
	}

	function contextFor(module: String): RustDecl {
		current = contexts.exists(module) ? contexts.get(module) : null;
		if(current == null) {
			current = new RustDecl(module, state);
			contexts.set(module, current);
			parts.set(module, []);
		}
		return current;
	}

	function inSourceScope(pos: haxe.macro.Expr.Position): Bool {
		final file = Context.getPosInfos(pos).file;
		for(root in Intercept.sourceRoots()) {
			final prefix = root.charAt(root.length - 1) == "/" ? root : root + "/";
			if(StringTools.startsWith(file, prefix)
				|| StringTools.startsWith(file, "./" + prefix)
				|| file.indexOf("/" + prefix) >= 0) {
				return true;
			}
		}
		return false;
	}

	function isSyntheticImpl(name: String): Bool {
		return StringTools.endsWith(name, "_Impl_");
	}

	function isInlineOnly(classType: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Bool {
		if(varFields.length == 0 && funcFields.length == 0) return true;
		if(varFields.length == 0 && funcFields.length > 0) {
			for(f in funcFields) {
				switch(f.field.kind) {
					case FMethod(MethInline) | FMethod(MethMacro):
					case _: return false;
				}
			}
			return true;
		}
		return false;
	}

	function packageOf(module: String): String {
		final parts = module.split(".");
		return parts.length > 1 ? parts.slice(0, -1).join(".") : "";
	}

	function moduleLeafName(module: String): String {
		final parts = module.split(".");
		return RustImports.toSnakeCase(parts[parts.length - 1]);
	}

	function modulePath(module: String): String {
		final parts = module.split(".").map(RustImports.toSnakeCase);
		return parts.join("/") + ".rs";
	}
}
#end
