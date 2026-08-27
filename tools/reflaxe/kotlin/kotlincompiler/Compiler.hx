package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import reflaxe.BaseCompiler.BaseCompilerFileOutputType;
import reflaxe.PluginCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	reflaxe plugin producing the Kotlin lane of the translatable subset.
**/
class Compiler extends PluginCompiler<Compiler> {
	/** Module-base name to declaration parts, in arrival order. */
	final parts: Map<String, Array<String>> = [];

	/** Module-base name to emission context. */
	final contexts: Map<String, KotlinDecl> = [];

	var current: Null<KotlinDecl> = null;

	public static function use() {
		ReflectCompiler.AddCompiler(new Compiler(), {
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
	}

	// ------------------------------------------------------------------
	// Declarations
	// ------------------------------------------------------------------

	public function compileClassImpl(classType: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Null<String> {
		if(!isBoringPack(classType.pack)) {
			return null;
		}
		if(classType.isExtern) {
			return null;
		}
		final decl = contextFor(classType.module);
		final result = decl.classDecl(classType, varFields, funcFields);
		if(result != null && result.length > 0) {
			parts.get(moduleBase(classType.module)).push(result);
		}
		return result;
	}

	public function compileEnumImpl(enumType: EnumType, options: Array<EnumOptionData>): Null<String> {
		if(!isBoringPack(enumType.pack)) {
			return null;
		}
		if(enumType.name == "VectorError") {
			// Handled in VectorException.kt
			return null;
		}
		final decl = contextFor(enumType.module);
		final result = decl.enumDecl(enumType, options);
		if(result != null && result.length > 0) {
			parts.get(moduleBase(enumType.module)).push(result);
		}
		return result;
	}

	public override function compileTypedef(def: DefType): Null<String> {
		if(!isBoringPack(def.pack)) {
			return null;
		}
		switch(def.type) {
			case TAnonymous(_):
			case _:
				return null;
		}
		final decl = contextFor(def.module);
		final result = decl.typedefDecl(def);
		if(result != null && result.length > 0) {
			parts.get(moduleBase(def.module)).push(result);
		}
		return result;
	}

	public function compileExpressionImpl(e: TypedExpr, topLevel: Bool): Null<String> {
		final decl = current != null ? current : new KotlinDecl("eval");
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
			final decl = contexts.get(module);
			final imports = decl.renderImports();
			final body = parts.get(module).join("\n\n");
			final content = imports
				+ (imports.length > 0 ? "\n" : "")
				+ body
				+ "\n";
			output.saveFile('boring/$module.kt', content);
		}
		output.saveFile("boring/BytesBuffer.kt", KotlinRuntime.BYTES_BUFFER_SOURCE);
		output.saveFile("boring/FPHelper.kt", KotlinRuntime.FP_HELPER_SOURCE);
		output.saveFile("boring/Console.kt", KotlinRuntime.CONSOLE_SOURCE);
		output.saveFile("boring/Process.kt", KotlinRuntime.PROCESS_SOURCE);
	}

	// ------------------------------------------------------------------
	// Internals
	// ------------------------------------------------------------------

	function contextFor(module: String): KotlinDecl {
		final base = moduleBase(module);
		current = contexts.exists(base) ? contexts.get(base) : null;
		if(current == null) {
			current = new KotlinDecl(base);
			contexts.set(base, current);
			parts.set(base, []);
		}
		return current;
	}

	function moduleBase(module: String): String {
		final segments = module.split(".");
		return segments[segments.length - 1];
	}

	function isBoringPack(pack: Array<String>): Bool {
		return pack.length == 1 && pack[0] == "boring";
	}
}
#end
