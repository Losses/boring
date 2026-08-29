package tscompiler;

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
	reflaxe plugin producing the TypeScript lane of the translatable
	subset (docs/specs/targets/07-reflaxe-typescript-target.md).

	Output layout is one file per Haxe module at the module's own path,
	plus a `runtime.ts` under the runtime-emit directory when runtime
	symbols are referenced, all written through the framework's output
	manager so `-D ts-output=<dir>` controls placement. Runtime files
	and runtime imports follow RuntimeConfig.
**/
class Compiler extends PluginCompiler<Compiler> {
	/** Module-base name to declaration parts, in arrival order. */
	final parts: Map<String, Array<String>> = [];

	/** Module-base name to emission context (imports per file). */
	final contexts: Map<String, TsDecl> = [];

	/** Modules that contain @:test methods and emit to the test tree. */
	final testModules: Map<String, Bool> = [];

	var current: Null<TsDecl> = null;

	public static function use() {
		ReflectCompiler.AddCompiler(new Compiler(), {
			fileOutputType: BaseCompilerFileOutputType.Manual,
			fileOutputExtension: ".ts",
			outputDirDefineName: "ts-output",
			unwrapTypedefs: false,
			normalizeEIE: false,
			preventRepeatVars: false,
			ignoreExterns: true,
		});
	}

	public function new() {
		super();
	}

	// ------------------------------------------------------------------
	// Declarations
	// ------------------------------------------------------------------

	public function compileClassImpl(classType: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Null<String> {
		// Resident runtime modules sit under src/runtime, outside the
		// sample source roots, but compile through this same pipeline.
		final isResident = RuntimeResidents.isResident(classType.module);
		if(classType.isExtern || (!isResident && !inSourceScope(classType.pos)) || isSyntheticImpl(classType.name) || isInlineOnly(classType, varFields, funcFields)) {
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
			final testOutput = Context.definedValue("ts-test-output");
			if(testOutput == null) {
				Context.error("ts-test-output define is required to emit tests", classType.pos);
			}
			final testRunner = Context.definedValue("ts-test-runner");
			if(testRunner == null || (testRunner != "node" && testRunner != "deno" && testRunner != "bun")) {
				Context.error("ts-test-runner define is required to emit tests (node | deno | bun)", classType.pos);
			}

			// Validate test methods
			final sortedFuncs = funcFields.copy();
			sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));

			final decl = contextFor(classType.module);
			testModules.set(classType.module, true);

			for(f in sortedFuncs) {
				if(!f.field.meta.has(":test")) {
					continue;
				}
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

				final testResult = decl.testFuncDecl(classType, f, testRunner);
				parts.get(classType.module).push(testResult);
			}
			return parts.get(classType.module).join("\n\n");
		}

		final decl = contextFor(classType.module);
		final result = decl.classDecl(classType, varFields, funcFields);
		parts.get(classType.module).push(result);
		return result;
	}

	public function compileEnumImpl(enumType: EnumType, options: Array<EnumOptionData>): Null<String> {
		if(!inSourceScope(enumType.pos)) {
			return null;
		}
		final decl = contextFor(enumType.module);
		final result = decl.enumDecl(enumType, options);
		parts.get(enumType.module).push(result);
		return result;
	}

	public override function compileTypedef(def: DefType): Null<String> {
		if(RuntimeResidents.isResident(def.module)) {
			// Resident typedefs sit under src/runtime, outside the
			// source scope, and lower to type aliases in the runtime
			// file (TsDecl.functionTypeDecl).
			final decl = contextFor(def.module);
			final result = decl.functionTypeDecl(def);
			parts.get(def.module).push(result);
			return result;
		}
		if(!inSourceScope(def.pos)) {
			return null;
		}
		switch(def.type) {
			case TAnonymous(_):
			case _:
				return null;
		}
		final decl = contextFor(def.module);
		final result = decl.typedefDecl(def);
		parts.get(def.module).push(result);
		return result;
	}

	/**
		Entry point for expressions the framework itself needs lowered
		(field initializers and the like). Everything flows through the
		same typed-AST translator as class bodies.
	**/
	public function compileExpressionImpl(e: TypedExpr, topLevel: Bool): Null<String> {
		final decl = current != null ? current : new TsDecl("eval");
		return topLevel ? decl.topLevelStatements(e) : decl.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Output
	// ------------------------------------------------------------------

	public override function generateFilesManually() {
		final modules = [];
		for(module in parts.keys()) modules.push(module);
		modules.sort(Reflect.compare);

		final tsOutput = Context.definedValue("ts-output");
		final testOutput = Context.definedValue("ts-test-output");
		final testRunner = Context.definedValue("ts-test-runner");

		for(module in modules) {
			if(RuntimeResidents.isResident(module)) {
				// Resident modules append into runtime.ts below,
				// not into the business tree.
				continue;
			}
			final decl = contexts.get(module);
			if(testModules.exists(module)) {
				final imports = decl.renderTestImports(testOutput, tsOutput, testRunner);
				final body = parts.get(module).join("\n\n");
				final content = '// Generated by the reflaxe TypeScript target. Do not edit.\n\n'
					+ imports
					+ (imports.length > 0 ? "\n" : "")
					+ body
					+ "\n";

				final suffix = testRunner == "deno" ? "_test.ts" : ".test.ts";
				final testFileRel = testOutput + "/" + module.split(".").join("/") + suffix;
				final savePath = TsImports.computeRelativePath(tsOutput, testFileRel);
				output.saveFile(savePath, content);
			} else {
				final imports = decl.renderImports();
				final body = parts.get(module).join("\n\n");
				final content = '// Generated by the reflaxe TypeScript target. Do not edit.\n\n'
					+ imports
					+ (imports.length > 0 ? "\n" : "")
					+ body
					+ "\n";
				output.saveFile(modulePath(module), content);
			}
		}
		final emitDir = RuntimeConfig.emitDir();
		if(emitDir != null && anyRuntimeUsed()) {
			// Resident modules compile through the normal pipeline and
			// append after the runtime source so runtime.ts stays one
			// self-contained file (docs/plans/2026-08-28 P4). The
			// table arrives as the compiled data-table field of
			// runtime.Graphemes, not a hand-wired render.
			final residentParts: Array<String> = [];
			for(resident in RuntimeResidents.MODULES) {
				final moduleParts = parts.get(resident);
				if(moduleParts != null && moduleParts.length > 0) {
					residentParts.push(moduleParts.join("\n\n"));
				}
			}
			output.saveFile(RuntimeConfig.emitPath(emitDir, "runtime.ts"), StringTools.trim(TsRuntime.SOURCE) + "\n" + residentParts.join("\n\n") + "\n");
			if(anyRuntimeTestUsed()) {
				// The test entry holds the host-file-system writer; the
				// general entry stays free of node imports so a browser
				// can load it (docs/plans/2026-08-28). Test residents
				// compile through the normal pipeline and append here,
				// the same self-contained shape as the general entry.
				final testResidentParts: Array<String> = [];
				for(resident in RuntimeResidents.TEST_MODULES) {
					final moduleParts = parts.get(resident);
					if(moduleParts != null && moduleParts.length > 0) {
						testResidentParts.push(moduleParts.join("\n\n"));
					}
				}
				output.saveFile(RuntimeConfig.emitPath(emitDir, "runtime/test.ts"), StringTools.trim(TsRuntime.TEST_SOURCE) + "\n" + testResidentParts.join("\n\n") + "\n");
			}
		}
	}

	function anyRuntimeTestUsed(): Bool {
		for(decl in contexts.iterator()) {
			if(decl.usesRuntimeTest()) {
				return true;
			}
		}
		return false;
	}

	function anyRuntimeUsed(): Bool {
		for(decl in contexts.iterator()) {
			if(decl.usesRuntime()) {
				return true;
			}
		}
		return false;
	}

	// ------------------------------------------------------------------
	// Internals
	// ------------------------------------------------------------------

	function contextFor(module: String): TsDecl {
		current = contexts.exists(module) ? contexts.get(module) : null;
		if(current == null) {
			current = new TsDecl(module);
			contexts.set(module, current);
			parts.set(module, []);
		}
		return current;
	}

	/**
		The compilation scope is the intercepted source roots: a
		declaration lowers when its position file lies under one of them,
		whatever its package. The output path mirrors the module path:
		`pack.Module` lands at `pack/Module.ts`.
	**/
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

	/** Haxe names synthesized abstract implementation classes `<Name>_Impl_`; they erase with the abstract. */
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

	function modulePath(module: String): String {
		return module.split(".").join("/") + ".ts";
	}
}
#end
