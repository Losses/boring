package reflaxe.kotlin;

#if (macro || reflaxe_runtime)
import reflaxe.BaseCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import haxe.macro.Context;
import haxe.macro.Type;

using StringTools;

class Compiler extends BaseCompiler {
	public static function use() {
		#if macro
		ReflectCompiler.AddCompiler(new Compiler(), {
			fileOutputType: Manual,
			outputDirDefineName: "kotlin-out",
			unwrapTypedefs: false,
			smartDCE: false,
			ignoreExterns: false,
			deleteOldOutput: false
		});
		#end
	}

	final fileOutputs:Map<String, String> = new Map();

	public function new() {
		super();
	}

	public override function shouldGenerateClass(cls:ClassType):Bool {
		if (cls.pack.length == 0 || cls.pack[0] != "boring") {
			return false;
		}
		return true;
	}

	public override function shouldGenerateEnum(enumType:EnumType):Bool {
		if (enumType.pack.length == 0 || enumType.pack[0] != "boring") {
			return false;
		}
		return true;
	}

	public function compileClassImpl(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Null<String> {
		Sys.println("compileClassImpl: " + classType.name);
		final code = KotlinClassHelper.compileClass(classType, varFields, funcFields);
		if (code != null) {
			final filename = "boring/" + classType.name + ".kt";
			fileOutputs.set(filename, code);
		}
		return code;
	}

	public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<String> {
		if (enumType.pack.length == 0 || enumType.pack[0] != "boring") {
			return null;
		}
		final code = KotlinEnumHelper.compileEnum(enumType, options);
		if (code != null) {
			final name = (enumType.name == "VectorError" || enumType.name == "VectorException") ? "VectorException" : enumType.name;
			final filename = "boring/" + name + ".kt";
			fileOutputs.set(filename, code);
		}
		return code;
	}

	public override function compileTypedef(defType:DefType):Null<String> {
		if (defType.pack.length == 0 || defType.pack[0] != "boring") {
			return null;
		}
		final code = KotlinTypedefHelper.compileTypedef(defType);
		if (code != null) {
			if (defType.name == "BoundsEm" || defType.name == "GlyphMetrics") {
				if (!fileOutputs.exists("boring/GlyphMetrics.kt")) {
					fileOutputs.set("boring/GlyphMetrics.kt", 'package boring\n\n/** Glyph bounding box in em units. */\nclass GlyphBounds(\n    val xMin: Double,\n    val yMin: Double,\n    val xMax: Double,\n    val yMax: Double\n)\n\n/** Fixed glyph metrics record shared by every language suite. */\nclass GlyphMetrics(\n    val codePoint: Int,\n    val advanceEm: Double,\n    val bounds: GlyphBounds\n)\n');
				}
			} else {
				fileOutputs.set("boring/" + defType.name + ".kt", code);
			}
		}
		return code;
	}

	public function compileExpressionImpl(expr:TypedExpr, topLevel:Bool):Null<String> {
		return null;
	}

	public override function generateFilesManually() {
		// Ensure Console.kt is present if Console extern was referenced
		if (!fileOutputs.exists("boring/Console.kt")) {
			fileOutputs.set("boring/Console.kt", 'package boring\n\n/**\n * Console logging utility mirroring the Haxe Console extern.\n */\nobject Console {\n    fun log(message: String) {\n        println(message)\n    }\n}\n');
		}

		for (path => content in fileOutputs) {
			output.saveFile(path, content);
		}
	}
}
#end
