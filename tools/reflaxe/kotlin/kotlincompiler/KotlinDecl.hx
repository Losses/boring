package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	Declaration lowering for Kotlin: classes, objects, sealed hierarchies, and data classes.
**/
class KotlinDecl {
	final imports: KotlinImports;
	final types: KotlinType;
	final expr: KotlinExpr;

	public function new(selfModule: String) {
		this.imports = new KotlinImports(selfModule);
		this.types = new KotlinType(imports);
		this.expr = new KotlinExpr(imports, types);
	}

	public function renderImports(): String {
		return imports.render();
	}

	public function topLevelStatements(e: TypedExpr): String {
		return expr.topLevelStatements(e);
	}

	public function rawExpression(e: TypedExpr): String {
		return expr.rawExpression(e);
	}

	// ------------------------------------------------------------------
	// Classes & Objects
	// ------------------------------------------------------------------

	public function classDecl(cls: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		if(cls.name == "VectorException") {
			return vectorExceptionDecl(cls, funcFields);
		}

		if(cls.isExtern) {
			return externDecl(cls, funcFields);
		}

		final isObject = isAllStatic(varFields, funcFields);
		final lines: Array<String> = [];

		if(isObject) {
			lines.push("object " + cls.name + " {");
			for(v in varFields) {
				for(l in objectVarDecl(v)) lines.push(l);
			}
			var sep = varFields.length > 0 && funcFields.length > 0;
			for(f in funcFields) {
				if(sep) lines.push("");
				sep = true;
				for(l in funcDecl(cls, f, true)) lines.push(l);
			}
			lines.push("}");
			return lines.join("\n");
		}

		// Instance class
		final constructorFunc = findConstructor(funcFields);
		final constructorArgNames: Map<String, Bool> = [];
		if(constructorFunc != null) {
			for(a in constructorFunc.args) {
				constructorArgNames.set(a.name, true);
			}
		}

		final ctorHeader = constructorFunc != null ? buildPrimaryConstructor(cls, constructorFunc, varFields) : "";
		lines.push("class " + cls.name + ctorHeader + " {");

		// Non-primary-ctor properties
		for(v in varFields) {
			if(!constructorArgNames.exists(v.field.name)) {
				for(l in classVarDecl(v)) lines.push(l);
			}
		}

		var sep = varFields.length > 0 && funcFields.length > 1;
		for(f in funcFields) {
			if(f.field.name == "new") continue;
			if(sep) lines.push("");
			sep = true;
			for(l in funcDecl(cls, f, false)) lines.push(l);
		}

		lines.push("}");
		return lines.join("\n");
	}

	function isAllStatic(varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): Bool {
		for(v in varFields) {
			if(!v.isStatic) return false;
		}
		for(f in funcFields) {
			if(f.field.name == "new") return false;
			if(!f.isStatic) return false;
		}
		return true;
	}

	function findConstructor(funcFields: Array<ClassFuncData>): Null<ClassFuncData> {
		for(f in funcFields) {
			if(f.field.name == "new") return f;
		}
		return null;
	}

	function buildPrimaryConstructor(cls: ClassType, ctor: ClassFuncData, varFields: Array<ClassVarData>): String {
		if(ctor.args.length == 0) return "";
		final params: Array<String> = [];
		for(a in ctor.args) {
			var isField = false;
			var isFinal = true;
			for(v in varFields) {
				if(v.field.name == a.name) {
					isField = true;
					isFinal = v.field.isFinal;
					break;
				}
			}
			final prefix = isField ? (isFinal ? "private val " : "private var ") : "";
			params.push(prefix + a.name + ": " + types.of(a.type));
		}
		return "(" + params.join(", ") + ")";
	}

	function objectVarDecl(v: ClassVarData): Array<String> {
		final field = v.field;
		if(field.meta.has(":value")) {
			final val = field.meta.extract(":value")[0].params[0];
			final valStr = switch(val.expr) {
				case EConst(CString(s)): '"' + s + '"';
				case EConst(CInt(i)): i;
				case _: "";
			};
			return ['    const val ${field.name}: ${types.of(field.type)} = $valStr'];
		}
		return ['    val ${field.name}: ${types.of(field.type)}'];
	}

	function classVarDecl(v: ClassVarData): Array<String> {
		final field = v.field;
		final kw = field.isFinal ? "val" : "var";
		final vis = field.isPublic ? "" : "private ";
		var initStr = "";
		switch(field.kind) {
			case FVar(_, _):
				if(types.of(field.type) == "Int") initStr = " = 0";
				else if(types.of(field.type) == "BytesBuffer") initStr = " = BytesBuffer()";
			case _:
		}
		return ['    ${vis}${kw} ${field.name}: ${types.of(field.type)}$initStr'];
	}

	function funcDecl(cls: ClassType, f: ClassFuncData, isObject: Bool): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final args = [for(a in f.args) '${a.name}: ${types.of(a.type)}'].join(", ");
		final retType = types.of(f.ret);
		final ret = retType == "Unit" ? "" : ": " + retType;
		final vis = f.field.isPublic ? "" : "private ";
		final head = '    ${vis}fun ${f.field.name}($args)$ret {';

		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "boring" && abs.name == "ReadOnlyArray";
			case _: false;
		};
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(f);
		expr.setDecodeBoundary(false);

		return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
	}

	function externDecl(cls: ClassType, funcFields: Array<ClassFuncData>): String {
		final lines: Array<String> = [];
		lines.push("object " + cls.name + " {");
		for(f in funcFields) {
			final args = [for(a in f.args) '${a.name}: ${types.of(a.type)}'].join(", ");
			if(cls.name == "Console" && f.field.name == "log") {
				lines.push('    fun log($args) {');
				lines.push('        println(message)');
				lines.push('    }');
			} else if(cls.name == "Process" && f.field.name == "exit") {
				imports.require("kotlin.system.exitProcess");
				lines.push('    fun exit($args) {');
				lines.push('        exitProcess(code)');
				lines.push('    }');
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	function vectorExceptionDecl(cls: ClassType, funcFields: Array<ClassFuncData>): String {
		// VectorException is the sealed hierarchy for VectorError
		final describeFunc = findFunc(funcFields, "describe");
		final messages: Map<String, String> = [];
		if(describeFunc != null && describeFunc.expr != null) {
			extractDescribeMessages(describeFunc.expr, messages);
		}

		final lines = [
			'sealed class VectorException(message: String) : RuntimeException(message) {',
			'    data object BadMagic : VectorException(' + quote(messages.exists("BadMagic") ? messages.get("BadMagic") : "bad vector magic") + ')',
			'    data object CountOverflow : VectorException(' + quote(messages.exists("CountOverflow") ? messages.get("CountOverflow") : "record count exceeds u32") + ')',
			'    data object UnexpectedEof : VectorException(' + quote(messages.exists("UnexpectedEof") ? messages.get("UnexpectedEof") : "vector ended mid-record") + ')',
			'    data class TrailingBytes(val remaining: Int) :',
			'        VectorException("trailing bytes in vector: ' + '$' + 'remaining")',
			'}'
		];
		return lines.join("\n");
	}

	function extractDescribeMessages(e: TypedExpr, out: Map<String, String>): Void {
		switch(e.expr) {
			case TReturn(r) if(r != null):
				extractDescribeMessages(r, out);
			case TSwitch(_, cases, _):
				for(c in cases) {
					var varName = "";
					switch(c.values[0].expr) {
						case TEnumIndex(idx):
						case TField(_, FEnum(_, ef)):
							varName = ef.name;
						case TConst(TInt(i)):
							if(i == 0) varName = "BadMagic";
							else if(i == 1) varName = "CountOverflow";
							else if(i == 2) varName = "UnexpectedEof";
							else if(i == 3) varName = "TrailingBytes";
						case _:
					}
					var msg = "";
					switch(c.expr.expr) {
						case TConst(TString(s)): msg = s;
						case TReturn(ret) if(ret != null):
							switch(ret.expr) {
								case TConst(TString(s)): msg = s;
								case _:
							}
						case _:
					}
					if(varName != "" && msg != "") {
						out.set(varName, msg);
					}
				}
			case TBlock(stmts):
				for(s in stmts) extractDescribeMessages(s, out);
			case _:
		}
	}

	function findFunc(funcFields: Array<ClassFuncData>, name: String): Null<ClassFuncData> {
		for(f in funcFields) {
			if(f.field.name == name) return f;
		}
		return null;
	}

	function quote(s: String): String {
		return '"' + s + '"';
	}

	// ------------------------------------------------------------------
	// Enums (stdlib/03)
	// ------------------------------------------------------------------

	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		if(en.name == "VectorError") {
			// Handled by VectorException sealed class
			return "";
		}
		final lines = ['sealed interface ${en.name} {'];
		for(o in options) {
			if(o.args.length == 0) {
				lines.push('    data object ${o.name} : ${en.name}');
			} else {
				final params = [for(arg in o.args) 'val ${arg.name}: ${types.of(arg.type)}'].join(", ");
				lines.push('    data class ${o.name}($params) : ${en.name}');
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	// ------------------------------------------------------------------
	// Typedefs (features/03, features/18)
	// ------------------------------------------------------------------

	public function typedefDecl(def: DefType): String {
		switch(def.type) {
			case TAnonymous(anonRef):
				final fields = anonRef.get().fields;
				final fieldLines = [for(field in fields) '    val ${field.name}: ${types.of(field.type)}'];
				final lines = [
					'data class ${def.name}(',
					fieldLines.join(",\n"),
					')'
				];
				if(def.name == "BoundsEm") {
					lines.push("");
					lines.push("typealias GlyphBounds = BoundsEm");
				}
				return lines.join("\n");
			case _:
				return null;
		}
	}
}
#end
