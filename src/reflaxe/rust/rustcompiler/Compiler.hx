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
		if(classType.isExtern || isSyntheticImpl(classType.name) || !inSourceScope(classType.pos)) {
			return null;
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
			// Folded into its exception class error enum.
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
			if(state.payloadEnumOwners.exists(module)) {
				continue;
			}
			final decl = contexts.get(module);
			final imports = decl.renderImports();
			final body = parts.get(module).join("\n\n");
			final content = imports
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
			final modNames = packages.get(pack);
			modNames.sort(Reflect.compare);
			final lines = [];
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

		// Emit runtime shims
		emitShim("haxe.io.FPHelper", "fp_helper.rs", RustRuntime.FP_HELPER_SOURCE);
		emitShim("haxe.io.BytesBuffer", "bytes_buffer.rs", RustRuntime.BYTES_BUFFER_SOURCE);
		emitShim("std.Console", "console.rs", RustRuntime.CONSOLE_SOURCE);
		emitShim("std.Process", "process.rs", RustRuntime.PROCESS_SOURCE);

		final emitDir = RuntimeConfig.emitDir();
		if(emitDir != null && hasAnyShim()) {
			final runtimeMods = [];
			if(state.shimsUsed.exists("haxe.io.FPHelper")) runtimeMods.push("fp_helper");
			if(state.shimsUsed.exists("haxe.io.BytesBuffer")) runtimeMods.push("bytes_buffer");
			if(state.shimsUsed.exists("std.Console")) runtimeMods.push("console");
			if(state.shimsUsed.exists("std.Process")) runtimeMods.push("process");
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
			if(p != "") {
				final sname = RustImports.toSnakeCase(p);
				libLines.push("pub mod " + sname + ";");
			}
		}
		if(emitDir != null && hasAnyShim()) {
			libLines.push("pub mod " + emitDir + ";");
		}
		libLines.push("");
		for(p in sortedPacks) {
			if(p != "") {
				final sname = RustImports.toSnakeCase(p);
				libLines.push("pub use " + sname + "::*;");
			}
		}
		output.saveFile("lib.rs", libLines.join("\n") + "\n");
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
												state.payloadEnumOwners.set(payload.module, payload.name);
												state.exceptionPayloads.set(cls.module, payload.module);
												state.errorModule = cls.module;
												state.errorName = payload.name;
											case _:
										}
									}
								case _:
							}
						}
					}
					for(f in cls.fields.get()) {
						scanForOverflowVariant(f.expr());
					}
					for(f in cls.statics.get()) {
						scanForOverflowVariant(f.expr());
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
							if(existing != null && existing.name != d.name) {
								Context.error("typedefs " + existing.name + " and " + d.name + " share one anonymous structure shape", d.pos);
								continue;
							}
							state.structTypedefs.set(sig, {module: d.module, name: d.name});
						case _:
					}
				case _:
			}
		}

		if(state.overflowVariant == null) {
			for(mt in mtypes) {
				switch(mt) {
					case TEnumDecl(e):
						final en = e.get();
						if(state.payloadEnumOwners.exists(en.module)) {
							for(construct in en.constructs) {
								if(construct.name.indexOf("Overflow") >= 0) {
									state.overflowVariant = construct.name;
									break;
								}
							}
						}
					case _:
				}
			}
		}
	}

	function scanForOverflowVariant(e: Null<TypedExpr>): Void {
		if(e == null) return;
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TIf(cond, thenExpr, _):
					final isNegativeCheck = switch(stripDecorations(cond).expr) {
						case TBinop(OpLt, _, r):
							switch(stripDecorations(r).expr) {
								case TConst(TInt(0)): true;
								case _: false;
							};
						case _: false;
					};
					if(isNegativeCheck) {
						extractThrowVariant(thenExpr);
					}
				case _:
			}
			haxe.macro.TypedExprTools.iter(x, walk);
		}
		walk(e);
	}

	function extractThrowVariant(e: TypedExpr): Void {
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TThrow(inner):
					switch(stripDecorations(inner).expr) {
						case TNew(_, _, args) if(args.length == 1):
							switch(stripDecorations(args[0]).expr) {
								case TField(_, FEnum(_, ef)):
									state.overflowVariant = ef.name;
								case TEnumParameter(_, ef, _):
									state.overflowVariant = ef.name;
								case TCall(fn, _):
									switch(stripDecorations(fn).expr) {
										case TField(_, FEnum(_, ef)):
											state.overflowVariant = ef.name;
										case _:
									}
								case _:
							}
						case _:
					}
				case _:
			}
			haxe.macro.TypedExprTools.iter(x, walk);
		}
		walk(e);
	}

	function stripDecorations(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): stripDecorations(inner);
			case _: e;
		};
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

	function modulePath(module: String): String {
		final segments = module.split(".");
		final snakeSegments = [for(s in segments) RustImports.toSnakeCase(s)];
		return snakeSegments.join("/") + ".rs";
	}

	function packageOf(module: String): String {
		final segments = module.split(".");
		return segments.length <= 1 ? "" : segments.slice(0, segments.length - 1).join(".");
	}

	function moduleLeafName(module: String): String {
		final segments = module.split(".");
		return RustImports.toSnakeCase(segments[segments.length - 1]);
	}
}
#end
