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
		if(classType.isExtern || isSyntheticImpl(classType.name) || isInlineOnly(classType, varFields, funcFields) || !inSourceScope(classType.pos)) {
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
			final decl = contexts.get(module);
			final imports = decl.renderImports();
			final body = parts.get(module).join("\n\n");
			final isTest = state.testModules.exists(module);
			final content = (isTest ? "#![cfg(test)]\n\n" : "")
				+ imports
				+ (imports.length > 0 ? "\n" : "")
				+ body
				+ "\n";
			output.saveFile(modulePath(module), content);

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
			output.saveFile(modPath, lines.join("\n") + "\n");
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
			output.saveFile("tests/mod.rs", lines.join("\n") + "\n");
		}

		// Emit runtime shims
		emitShim("haxe.io.FPHelper", "fp_helper.rs", RustRuntime.FP_HELPER_SOURCE);
		emitShim("haxe.io.BytesBuffer", "bytes_buffer.rs", RustRuntime.BYTES_BUFFER_SOURCE);
		emitShim("std.Console", "console.rs", RustRuntime.CONSOLE_SOURCE);
		emitShim("std.Process", "process.rs", RustRuntime.PROCESS_SOURCE);
		emitShim("std.Test", "test.rs", RustRuntime.TEST_SOURCE);
		if(state.shimsUsed.exists("std.SortedSet") || state.shimsUsed.exists("std.SortedSetBuilder")) {
			state.shimsUsed.set("std.SortedSet", true);
			state.shimsUsed.set("std.SortedMap", true);
			emitShim("std.SortedSet", "sorted_set.rs", RustRuntime.SORTED_SET_SOURCE);
		}
		if(state.shimsUsed.exists("std.SortedMap") || state.shimsUsed.exists("std.SortedMapBuilder")) {
			state.shimsUsed.set("std.SortedMap", true);
			emitShim("std.SortedMap", "sorted_map.rs", RustRuntime.SORTED_MAP_SOURCE);
		}

		final emitDir = RuntimeConfig.emitDir();
		if(emitDir != null && hasAnyShim()) {
			final runtimeMods = [];
			if(state.shimsUsed.exists("haxe.io.FPHelper")) runtimeMods.push("fp_helper");
			if(state.shimsUsed.exists("haxe.io.BytesBuffer")) runtimeMods.push("bytes_buffer");
			if(state.shimsUsed.exists("std.Console")) runtimeMods.push("console");
			if(state.shimsUsed.exists("std.Process")) runtimeMods.push("process");
			if(state.shimsUsed.exists("std.Test")) runtimeMods.push("test");
			if(state.shimsUsed.exists("std.SortedMap") || state.shimsUsed.exists("std.SortedMapBuilder")) runtimeMods.push("sorted_map");
			if(state.shimsUsed.exists("std.SortedSet") || state.shimsUsed.exists("std.SortedSetBuilder")) runtimeMods.push("sorted_set");
			runtimeMods.sort(Reflect.compare);
			final rtLines = [];
			for(m in runtimeMods) rtLines.push("pub mod " + m + ";");
			rtLines.push("");
			for(m in runtimeMods) rtLines.push("pub use " + m + "::*;");
			output.saveFile(RuntimeConfig.emitPath(emitDir, "mod.rs"), rtLines.join("\n") + "\n");
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
		output.saveFile("lib.rs", libLines.join("\n") + "\n");
	}

	function generateTestHelper(): Void {
		final lines = [
			"// Generated test helper for type-guided assertions (Ruling C)",
			"#![allow(unused_imports, dead_code)]",
			"",
			"use crate::runtime::test as testlib;",
			"",
			"pub fn equals_bytes(a: &[u8], b: &[u8]) -> bool { a == b }",
			"pub fn format_bytes(v: &[u8]) -> String { testlib::format_bytes(v) }",
			"pub fn assert_equals_bytes(expected: &[u8], actual: &[u8], message: Option<&str>) {",
			"    if !equals_bytes(expected, actual) {",
			"        testlib::report_failure(message, &format_bytes(expected), &format_bytes(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_bool(a: &bool, b: &bool) -> bool { *a == *b }",
			"pub fn format_bool(v: &bool) -> String { if *v { \"true\".to_string() } else { \"false\".to_string() } }",
			"pub fn assert_equals_bool(expected: &bool, actual: &bool, message: Option<&str>) {",
			"    if !equals_bool(expected, actual) {",
			"        testlib::report_failure(message, &format_bool(expected), &format_bool(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_i32(a: &i32, b: &i32) -> bool { *a == *b }",
			"pub fn format_i32(v: &i32) -> String { v.to_string() }",
			"pub fn assert_equals_i32(expected: &i32, actual: &i32, message: Option<&str>) {",
			"    if !equals_i32(expected, actual) {",
			"        testlib::report_failure(message, &format_i32(expected), &format_i32(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_f64(a: &f64, b: &f64) -> bool { *a == *b }",
			"pub fn format_f64(v: &f64) -> String { testlib::format_float(*v) }",
			"pub fn assert_equals_f64(expected: &f64, actual: &f64, message: Option<&str>) {",
			"    if !equals_f64(expected, actual) {",
			"        testlib::report_failure(message, &format_f64(expected), &format_f64(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_u32(a: &u32, b: &u32) -> bool { *a == *b }",
			"pub fn format_u32(v: &u32) -> String { v.to_string() }",
			"pub fn assert_equals_u32(expected: &u32, actual: &u32, message: Option<&str>) {",
			"    if !equals_u32(expected, actual) {",
			"        testlib::report_failure(message, &format_u32(expected), &format_u32(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_u16(a: &u16, b: &u16) -> bool { *a == *b }",
			"pub fn format_u16(v: &u16) -> String { v.to_string() }",
			"pub fn assert_equals_u16(expected: &u16, actual: &u16, message: Option<&str>) {",
			"    if !equals_u16(expected, actual) {",
			"        testlib::report_failure(message, &format_u16(expected), &format_u16(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_usize(a: &usize, b: &usize) -> bool { *a == *b }",
			"pub fn format_usize(v: &usize) -> String { v.to_string() }",
			"pub fn assert_equals_usize(expected: &usize, actual: &usize, message: Option<&str>) {",
			"    if !equals_usize(expected, actual) {",
			"        testlib::report_failure(message, &format_usize(expected), &format_usize(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_string(a: &String, b: &String) -> bool { a == b }",
			"pub fn format_string(v: &String) -> String { testlib::format_string(v) }",
			"pub fn assert_equals_string(expected: &String, actual: &String, message: Option<&str>) {",
			"    if !equals_string(expected, actual) {",
			"        testlib::report_failure(message, &format_string(expected), &format_string(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_opt_string(a: &Option<String>, b: &Option<String>) -> bool { a == b }",
			"pub fn format_opt_string(v: &Option<String>) -> String { match v { Some(s) => testlib::format_string(s), None => \"null\".to_string() } }",
			"pub fn assert_equals_opt_string(expected: &Option<String>, actual: &Option<String>, message: Option<&str>) {",
			"    if !equals_opt_string(expected, actual) {",
			"        testlib::report_failure(message, &format_opt_string(expected), &format_opt_string(actual));",
			"    }",
			"}",
			"",
			"pub fn equals_opt_u32(a: &Option<u32>, b: &Option<u32>) -> bool { a == b }",
			"pub fn format_opt_u32(v: &Option<u32>) -> String { match v { Some(x) => x.to_string(), None => \"null\".to_string() } }",
			"pub fn assert_equals_opt_u32(expected: &Option<u32>, actual: &Option<u32>, message: Option<&str>) {",
			"    if !equals_opt_u32(expected, actual) {",
			"        testlib::report_failure(message, &format_opt_u32(expected), &format_opt_u32(actual));",
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
					lines.push('pub fn assert_equals_vec_$safeSnake(expected: &[$elemTypeStr], actual: &[$elemTypeStr], message: Option<&str>) {');
					lines.push('    if !equals_vec_$safeSnake(expected, actual) {');
					lines.push('        testlib::report_failure(message, &format_vec_$safeSnake(expected), &format_vec_$safeSnake(actual));');
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
					lines.push('pub fn assert_equals_vec_$safeSnake(expected: &[$elemTypeStr], actual: &[$elemTypeStr], message: Option<&str>) {');
					lines.push('    if !equals_vec_$safeSnake(expected, actual) {');
					lines.push('        testlib::report_failure(message, &format_vec_$safeSnake(expected), &format_vec_$safeSnake(actual));');
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
							lines.push('pub fn assert_equals_$safeSnake(expected: &$structPath, actual: &$structPath, message: Option<&str>) {');
							lines.push('    if !equals_$safeSnake(expected, actual) {');
							lines.push('        testlib::report_failure(message, &format_$safeSnake(expected), &format_$safeSnake(actual));');
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
					lines.push('pub fn assert_equals_$safeSnake(expected: &$enumPath, actual: &$enumPath, message: Option<&str>) {');
					lines.push('    if !equals_$safeSnake(expected, actual) {');
					lines.push('        testlib::report_failure(message, &format_$safeSnake(expected), &format_$safeSnake(actual));');
					lines.push('    }');
					lines.push('}');
				case _:
			}
		}
		output.saveFile("tests/test_helper.rs", lines.join("\n") + "\n");
	}

	function rustType(t: Type): String {
		return switch(t) {
			case TAbstract(a, params):
				final abs = a.get();
				switch(abs.pack.concat([abs.name]).join(".")) {
					case "Int": "u32";
					case "Float": "f64";
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
			if(s == "u32" || s == "u16" || s == "usize" || s == "i32" || s == "i64" || s == "f64" || s == "bool") {
				return s;
			}
			if(s == "String") return "string";
			if(s == "Vec<u8>") return "bytes";
		}
		return switch(t) {
			case TAbstract(a, _):
				switch(a.get().name) {
					case "Int": "i32";
					case "Float": "f64";
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
		output.saveFile(path, StringTools.trim(source) + "\n");
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
