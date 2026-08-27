package kotlincompiler;

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
	reflaxe plugin producing the Kotlin lane of the translatable subset.

	Output layout is one file per Haxe module at the module's own path,
	plus runtime shims for the standard library on demand, all written
	through the framework's output manager so `-D kotlin-output=<dir>`
	controls placement.

	The compilation scope is the intercepted source roots: a declaration
	lowers when its position file lies under one of them, whatever its
	package.
**/
class Compiler extends PluginCompiler<Compiler> {
	/** Module path to declaration parts, in arrival order. */
	final parts: Map<String, Array<String>> = [];

	/** Module path to emission context. */
	final contexts: Map<String, KotlinDecl> = [];

	final state: KotlinEmissionState;

	var current: Null<KotlinDecl> = null;

	public static function use() {
		final compiler = new Compiler();
		// Registered before the framework's own callback so the linkage
		// scan completes before any per-declaration lowering runs.
		haxe.macro.Context.onAfterTyping(compiler.preScan);
		ReflectCompiler.AddCompiler(compiler, {
			fileOutputType: BaseCompilerFileOutputType.Manual,
			fileOutputExtension: ".kt",
			outputDirDefineName: "kotlin-output",
			unwrapTypedefs: false,
			normalizeEIE: false,
			preventRepeatVars: false,
			ignoreExterns: true,
		});
	}

	public function new() {
		super();
		state = new KotlinEmissionState();
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
			// Folded into its exception class as the sealed hierarchy.
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
		final decl = current != null ? current : new KotlinDecl("eval", state);
		return topLevel ? decl.topLevelStatements(e) : decl.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Output
	// ------------------------------------------------------------------

	public override function generateFilesManually() {
		final modules = [];
		for(module in parts.keys()) modules.push(module);
		modules.sort(Reflect.compare);
		for(module in modules) {
			if(state.payloadEnumOwners.exists(module)) {
				// The sealed fold already carries these variants.
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
		}
		emitShim("haxe.io.FPHelper", "FPHelper.kt", KotlinRuntime.FP_HELPER_SOURCE);
		emitShim("haxe.io.BytesBuffer", "BytesBuffer.kt", KotlinRuntime.BYTES_BUFFER_SOURCE);
		emitShim("std.Console", "Console.kt", KotlinRuntime.CONSOLE_SOURCE);
		emitShim("std.Process", "Process.kt", KotlinRuntime.PROCESS_SOURCE);
	}

	/**
		Writes a used shim into the runtime-emit directory under the
		configured runtime package. Bring-your-own mode writes nothing;
		the references already point at the consumer's package.
	**/
	function emitShim(module: String, fileName: String, source: String): Void {
		if(!state.shimsUsed.exists(module)) {
			return;
		}
		final dir = RuntimeConfig.emitDir();
		if(dir == null) {
			return;
		}
		final runtimePackage = RuntimeConfig.requireImportName("module " + module);
		final path = RuntimeConfig.emitPath(dir, fileName);
		output.saveFile(path, "package " + runtimePackage + "\n\n" + StringTools.trim(source) + "\n");
	}

	// ------------------------------------------------------------------
	// Internals
	// ------------------------------------------------------------------

	/**
		Walks every typed module once, before per-declaration lowering,
		recording the exception-payload linkage of the sealed fold. The
		scan runs ahead of the lowering pass so the linkage is visible
		whatever order the typer hands declarations over in.
	**/
	function preScan(mtypes: Array<haxe.macro.Type.ModuleType>): Void {
		for(mt in mtypes) {
			switch(mt) {
				case TClassDecl(c):
					final cls = c.get();
					if(cls.isExtern || isSyntheticImpl(cls.name) || !inSourceScope(cls.pos)) {
						continue;
					}
					if(!KotlinDecl.isExceptionSubclass(cls)) {
						continue;
					}
					// The constructor lives apart from the instance fields.
					final ctor = cls.constructor != null ? cls.constructor.get() : null;
					if(ctor == null) {
						continue;
					}
					switch(ctor.type) {
						case TFun(args, _):
							for(a in args) {
								switch(a.t) {
									case TEnum(e, _):
										final payload = e.get();
										state.payloadEnumOwners.set(payload.module, cls.name);
										state.exceptionPayloads.set(cls.module, payload.module);
									case _:
								}
							}
						case _:
					}
				case TTypeDecl(def):
					final d = def.get();
					if(!inSourceScope(d.pos)) {
						continue;
					}
					switch(d.type) {
						case TAnonymous(anon):
							final sig = KotlinDecl.structureSignature(anon);
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
	}

	function contextFor(module: String): KotlinDecl {
		current = contexts.exists(module) ? contexts.get(module) : null;
		if(current == null) {
			current = new KotlinDecl(module, state);
			contexts.set(module, current);
			parts.set(module, []);
		}
		return current;
	}

	/**
		The compilation scope is the intercepted source roots; a
		declaration from any package lowers the same way. The output path
		mirrors the module path: `pack.Module` lands at `pack/Module.kt`.
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

	function modulePath(module: String): String {
		return module.split(".").join("/") + ".kt";
	}
}
#end
