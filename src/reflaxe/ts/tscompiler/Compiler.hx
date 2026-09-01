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
	subset (docs/specs/features/14-type-system-mapping.md).

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
		// number is binary64 with no binary32 alias in the language, so
		// the f32 lane has no faithful TypeScript lowering; reject at
		// plugin registration, before any type rendering (feature
		// spec 23).
		if(FloatPrecision.isF32()) {
			Context.error("float-precision=f32 is not available on the TypeScript target: number is binary64; compile without the define for f64 semantics", Context.currentPos());
		}
		Context.onAfterTyping(ValueTypeSupport.validateModules);
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
		final valueType = ValueTypeSupport.infoOfClass(classType);
		if(valueType != null) {
			if(!ValueTypeSupport.isValidAbstract(valueType.abstractType)) {
				return null;
			}
			StaticFunctionMarkers.validateAll(funcFields);
			final decl = contextFor(classType.module);
			final result = decl.valueTypeDecl(classType, valueType, varFields, funcFields);
			parts.get(classType.module).push(result);
			return result;
		}
		if(classType.isExtern || (!isResident && !inSourceScope(classType.pos))) {
			return null;
		}
		SealedVariantHelper.validateClass(classType);
		if(isSyntheticImpl(classType.name) || (!classType.isInterface && isInlineOnly(classType, varFields, funcFields))) {
			return null;
		}
		StaticFunctionMarkers.validateAll(funcFields);

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

			// Test classes carry test functions and nothing else (feature
			// spec 27); shared logic belongs in an ordinary class, whose
			// member lowering every target already renders.
			for(v in varFields) {
				Context.error("test class " + classType.name + " carries a non-test member " + v.field.name + "; shared logic belongs in an ordinary class", v.field.pos);
			}

			final decl = contextFor(classType.module);
			testModules.set(classType.module, true);

			for(f in sortedFuncs) {
				if(!f.field.meta.has(":test")) {
					// Test classes carry test functions and nothing else
					// (feature spec 27); shared logic belongs in an
					// ordinary class, whose member lowering every target
					// already renders.
					Context.error("test class " + classType.name + " carries a non-test member " + f.field.name + "; shared logic belongs in an ordinary class", f.field.pos);
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
		SealedVariantHelper.validateEnum(enumType);
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
		SealedVariantHelper.validateTypedef(def);
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
				final body = parts.get(module).join("\n\n") + ExternBindings.appendix(module);
				final content = '// Generated by the reflaxe TypeScript target. Do not edit.\n\n'
					+ imports
					+ (imports.length > 0 ? "\n" : "")
					+ body
					+ "\n";

				final suffix = testRunner == "deno" ? "_test.ts" : ".test.ts";
				final testFileRel = testOutput + "/" + module.split(".").join("/") + suffix;
				final savePath = TsImports.computeRelativePath(tsOutput, testFileRel);
				saveTreeFile(savePath, content);
			} else {
				final imports = decl.renderImports();
				final body = parts.get(module).join("\n\n") + ExternBindings.appendix(module);
				final content = '// Generated by the reflaxe TypeScript target. Do not edit.\n\n'
					+ imports
					+ (imports.length > 0 ? "\n" : "")
					+ body
					+ "\n";
				saveTreeFile(modulePath(module), content);
			}
		}
		for(module in ExternBindings.modules()) {
			// Modules whose declarations are all externs never enter
			// `parts`; their referenced names still import the module
			// path, so one binding file per such module completes the
			// tree. A referenced module with neither parts nor extern
			// bindings would leave a dangling import; that is an error.
			if(parts.exists(module)) {
				continue;
			}
			final bindings = ExternBindings.render(module);
			if(bindings.length == 0) {
				Context.error("module " + module + " is value-referenced but emits no declarations and holds no extern classes", Context.currentPos());
			}
			saveTreeFile(modulePath(module), '// Generated by the reflaxe TypeScript target. Do not edit.\n\n' + bindings + "\n");
		}
		final emitDir = RuntimeConfig.emitDir();
		if(emitDir != null && anyRuntimeUsed()) {
			// Resident modules compile through the normal pipeline and
			// append after the runtime source so runtime.ts stays one
			// self-contained file. The
			// table arrives as the compiled data-table field of
			// runtime.Graphemes. The generated runtime uses that field.
			final residentParts: Array<String> = [];
			for(resident in RuntimeResidents.MODULES) {
				final moduleParts = parts.get(resident);
				if(moduleParts != null && moduleParts.length > 0) {
					residentParts.push(moduleParts.join("\n\n"));
				}
			}
			saveTreeFile(RuntimeConfig.emitPath(emitDir, "runtime.ts"), StringTools.trim(TsRuntime.SOURCE) + "\n" + residentParts.join("\n\n") + "\n");
			if(anyRuntimeTestUsed()) {
				// The test entry holds the host-file-system writer; the
				// general entry stays free of node imports so a browser
				// can load it. Test residents
				// compile through the normal pipeline and append here,
				// the same self-contained shape as the general entry.
				final testResidentParts: Array<String> = [];
				for(resident in RuntimeResidents.TEST_MODULES) {
					final moduleParts = parts.get(resident);
					if(moduleParts != null && moduleParts.length > 0) {
						testResidentParts.push(moduleParts.join("\n\n"));
					}
				}
				saveTreeFile(RuntimeConfig.emitPath(emitDir, "runtime/test.ts"), StringTools.trim(TsRuntime.TEST_SOURCE) + "\n" + testResidentParts.join("\n\n") + "\n");
			}
		}

		if(PackageShell.enabled()) {
			emitPackageShell();
		}
		if(PackageArtifacts.enabled()) {
			PackageArtifacts.requireShell();
			emitNpmArtifact(tsOutput);
		}
	}

	/**
		Saves one file through the output manager and records the write
		for artifact packing (feature spec 25). Paths that escape the
		output root are recorded away by the filter in PackageArtifacts.
	**/
	function saveTreeFile(path: String, content: String): Void {
		output.saveFile(path, content);
		PackageArtifacts.record(path, content);
	}

	/**
		Writes package.json beside the generated tree (feature spec 24).
		The tree is TypeScript source, so the manifest carries the module
		type and a typescript devDependency for consumers that typecheck.
		The exports map exposes the emitted top-level entries through
		directory wildcards plus the runtime entry; test trees stay
		unexposed. The validity condition is a relative runtime import:
		a by-name import names a package coordinate no manifest can
		declare.
	**/
	function emitPackageShell(): Void {
		final runtimeImport = RuntimeConfig.importName();
		if(anyRuntimeUsed() && runtimeImport != null && !TsImports.isRelativeSpecifier(runtimeImport)) {
			Context.error("package shell requires a relative runtime import: a by-name runtime import names a package the manifest cannot declare; pass runtime-import a relative specifier or package-shell none", Context.currentPos());
		}
		final license = PackageShell.license();
		final lines = [
			"{",
			'  "name": ${jsonString(PackageShell.name())},',
			'  "version": ${jsonString(PackageShell.version())},',
		];
		if(license != null) {
			lines.push('  "license": ${jsonString(license)},');
		}
		lines.push('  "private": true,');
		lines.push('  "type": "module",');
		final exportLines = packageShellExports();
		if(exportLines.length > 0) {
			lines.push('  "exports": {');
			for(index in 0...exportLines.length) {
				final comma = index < exportLines.length - 1 ? "," : "";
				lines.push('    ${jsonString(exportLines[index].key)}: ${jsonString(exportLines[index].target)}${comma}');
			}
			lines.push("  },");
		}
		lines.push('  "devDependencies": {');
		lines.push('    "typescript": "^5.9.0"');
		lines.push('  }');
		lines.push("}");
		saveTreeFile("package.json", lines.join("\n") + "\n");
	}

	/**
		The exports entries of the manifest: one directory wildcard per
		emitted top-level package directory, one file entry per top-level
		file module, and the runtime entry when the compilation emitted a
		runtime. Test modules and residents are not business modules and
		stay unexposed. Keys sort so identical compilations emit
		identical bytes.
	**/
	function packageShellExports(): Array<{key: String, target: String}> {
		final directories: Array<String> = [];
		final files: Array<String> = [];
		for(module in parts.keys()) {
			if(RuntimeResidents.isResident(module) || testModules.exists(module)) {
				continue;
			}
			final segments = module.split(".");
			final topLevel = segments[0];
			final bucket = segments.length > 1 ? directories : files;
			if(bucket.indexOf(topLevel) < 0) {
				bucket.push(topLevel);
			}
		}
		final entries: Array<{key: String, target: String}> = [];
		for(directory in directories) {
			entries.push({key: './${directory}/*', target: './${directory}/*.ts'});
		}
		for(file in files) {
			entries.push({key: './${file}', target: './${file}.ts'});
		}
		final emitDir = RuntimeConfig.emitDir();
		if(anyRuntimeUsed() && emitDir != null) {
			entries.push({key: "./runtime", target: "./" + RuntimeConfig.emitPath(emitDir, "runtime.ts")});
		}
		entries.sort((a, b) -> Reflect.compare(a.key, b.key));
		return entries;
	}

	/**
		Packs the npm artifact (feature spec 25). The artifact manifest
		retargets the exports map of spec 24 at the compiled files: the
		source tree's manifest points consumers at `.ts`, while the
		tarball carries the `dist/` output of `package-tsc` and its
		manifest points at `.js` with a `types` condition. The manifest
		drops `private` (the tarball exists to travel through a
		registry) and the typescript devDependency (the artifact
		carries declarations, so consumers never typecheck it). The
		runtime test entry stays out of the compile set: it imports
		node:fs for the repository's test harness and has no role in an
		installed package.
	**/
	function emitNpmArtifact(outputDir: String): Void {
		final excluded: Array<String> = [];
		final emitDir = RuntimeConfig.emitDir();
		if(emitDir != null && anyRuntimeTestUsed()) {
			excluded.push(RuntimeConfig.emitPath(emitDir, "runtime/test.ts"));
		}
		PackageArtifacts.emitNpmTarGz(outputDir, npmArtifactManifest(), excluded);
	}

	/** The manifest packed into the npm tarball, aimed at `dist/`. */
	function npmArtifactManifest(): String {
		final license = PackageShell.license();
		final lines = [
			"{",
			'  "name": ${jsonString(PackageShell.name())},',
			'  "version": ${jsonString(PackageShell.version())},',
		];
		if(license != null) {
			lines.push('  "license": ${jsonString(license)},');
		}
		lines.push('  "type": "module",');
		lines.push('  "exports": {');
		final exportEntries = packageShellExports();
		for(index in 0...exportEntries.length) {
			// One target of the shape "./pack/*.ts" loses its "./"
			// prefix and ".ts" suffix and becomes the dist stem
			// "pack/*".
			final target = exportEntries[index].target;
			final stem = target.substring(2, target.length - 3);
			final comma = index < exportEntries.length - 1 ? "," : "";
			lines.push('    ${jsonString(exportEntries[index].key)}: {');
			lines.push('      "types": ${jsonString("./dist/" + stem + ".d.ts")},');
			lines.push('      "default": ${jsonString("./dist/" + stem + ".js")}');
			lines.push('    }' + comma);
		}
		lines.push("  }");
		lines.push("}");
		return lines.join("\n") + "\n";
	}

	/** A JSON string literal with the two escapes a manifest value needs. */
	static function jsonString(value: String): String {
		final escaped = StringTools.replace(value, "\\", "\\\\");
		return '"' + StringTools.replace(escaped, '"', '\\"') + '"';
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
