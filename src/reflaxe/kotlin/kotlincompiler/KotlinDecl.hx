package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	Declaration lowering for Kotlin: classes, objects, sealed error
	hierarchies, and data classes. Every emission derives from the typed
	AST; the exception fold reads the payload enum's options and the
	message function's switch cases.
**/
class KotlinDecl {
	final imports: KotlinImports;
	final types: KotlinType;
	final expr: KotlinExpr;

	public function new(selfModule: String, state: KotlinEmissionState) {
		this.imports = new KotlinImports(selfModule, state);
		this.types = new KotlinType(imports, state);
		this.expr = new KotlinExpr(imports, types, state);
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
		if(cls.isInterface) {
			final lines: Array<String> = [];
			lines.push("interface " + cls.name + " {");
			for(f in funcFields) {
				final args = [for(a in f.args) '${a.name}: ${types.of(a.type)}'].join(", ");
				final retType = types.of(f.ret);
				final ret = retType == "Unit" ? "" : ": " + retType;
				lines.push('    fun ${f.field.name}($args)$ret');
			}
			lines.push("}");
			return lines.join("\n");
		}

		if(isExceptionSubclass(cls)) {
			final payload = payloadEnumOf(funcFields);
			if(payload == null) {
				Context.error("exception subclass without a payload enum constructor has no Kotlin lowering", cls.pos);
				return null;
			}
			return sealedExceptionDecl(cls, payload, funcFields);
		}

		var hasTestMethods = false;
		for(f in funcFields) {
			if(f.field.meta.has(":test")) {
				hasTestMethods = true;
				break;
			}
		}

		if(hasTestMethods) {
			final lines: Array<String> = [];
			lines.push("class " + cls.name + " {");
			var sep = false;
			final sortedFuncs = funcFields.copy();
			sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));
			for(f in sortedFuncs) {
				if(!f.field.meta.has(":test")) continue;
				if(sep) lines.push("");
				sep = true;
				for(l in testFuncDecl(cls, f)) lines.push(l);
			}
			lines.push("}");
			return lines.join("\n");
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
		final ifaceStr = cls.interfaces.length > 0 ? " : " + [for(i in cls.interfaces) i.t.get().name].join(", ") : "";
		lines.push("class " + cls.name + ctorHeader + ifaceStr + " {");

		// Non-primary-ctor properties
		for(v in varFields) {
			if(!constructorArgNames.exists(v.field.name)) {
				for(l in classVarDecl(v)) lines.push(l);
			}
		}

		final instanceFuncs = [for(f in funcFields) if(!f.isStatic && f.field.name != "new") f];
		final staticFuncs = [for(f in funcFields) if(f.isStatic) f];

		var sep = varFields.length > 0 && instanceFuncs.length > 0;
		for(f in instanceFuncs) {
			if(sep) lines.push("");
			sep = true;
			for(l in funcDecl(cls, f, false)) lines.push(l);
		}

		if(staticFuncs.length > 0) {
			if(instanceFuncs.length > 0 || varFields.length > 0) lines.push("");
			lines.push("    companion object {");
			var csep = false;
			for(f in staticFuncs) {
				if(csep) lines.push("");
				csep = true;
				for(l in funcDecl(cls, f, true)) lines.push("    " + l);
			}
			lines.push("    }");
		}

		lines.push("}");
		return lines.join("\n");
	}

	/** A haxe.Exception subclass folds, with its payload enum, into a sealed hierarchy. */
	public static function isExceptionSubclass(cls: ClassType): Bool {
		if(cls.superClass == null) {
			return false;
		}
		final parent = cls.superClass.t.get();
		return parent.pack.join(".") == "haxe" && parent.name == "Exception";
	}

	/**
		Signature identifying an anonymous structure: its field names and
		types, sorted. Nominal lowering matches object literals against
		typedefs through this signature.
	**/
	public static function structureSignature(anon: Ref<AnonType>): String {
		final entries = [for(f in anon.get().fields) f.name + ":" + Std.string(f.type)];
		entries.sort(Reflect.compare);
		return entries.join(";");
	}

	function payloadEnumOf(funcFields: Array<ClassFuncData>): Null<EnumType> {
		final ctor = findConstructor(funcFields);
		if(ctor == null) {
			return null;
		}
		for(a in ctor.args) {
			switch(a.type) {
				case TEnum(e, _):
					return e.get();
				case _:
			}
		}
		return null;
	}

	/**
		The message function is the class's static function taking the
		payload enum and returning String; its switch supplies each
		variant's super-call argument.
	**/
	function findMessageFunc(cls: ClassType, funcFields: Array<ClassFuncData>, payload: EnumType): Null<ClassFuncData> {
		var found: Null<ClassFuncData> = null;
		for(f in funcFields) {
			if(!f.isStatic || f.args.length != 1) {
				continue;
			}
			switch(f.args[0].type) {
				case TEnum(e, _):
					if(e.get().module == payload.module) {
						if(found != null) {
							Context.error("exception class carries more than one message function", cls.pos);
							return null;
						}
						found = f;
					}
				case _:
			}
		}
		return found;
	}

	function sealedExceptionDecl(cls: ClassType, payload: EnumType, funcFields: Array<ClassFuncData>): String {
		final options = [for(_ => ef in payload.constructs) ef];
		options.sort((a, b) -> Reflect.compare(a.index, b.index));

		final messageFunc = findMessageFunc(cls, funcFields, payload);
		if(messageFunc == null || messageFunc.expr == null) {
			Context.error("exception class carries no message function for its payload enum", cls.pos);
			return null;
		}
		final messages = new Map<String, String>();
		collectMessageCases(messageFunc.expr, options, messages);

		final lines = [
			'sealed class ${cls.name}(message: String) : RuntimeException(message) {'
		];
		for(o in options) {
			final message = messages.get(o.name);
			if(message == null) {
				Context.error("message function misses a case for " + o.name, cls.pos);
				return null;
			}
			final args = enumFieldParams(o);
			if(args.length == 0) {
				lines.push('    data object ${o.name} : ${cls.name}(${message})');
			} else {
				final params = [for(arg in args) 'val ${arg.name}: ${types.of(arg.type)}'].join(", ");
				lines.push('    data class ${o.name}($params) :');
				lines.push('        ${cls.name}(${message})');
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	/** Constructor argument names and types, read off the enum field's function type. */
	function enumFieldParams(ef: haxe.macro.Type.EnumField): Array<{name: String, type: Type}> {
		return switch(ef.type) {
			case TFun(args, _): [for(a in args) {name: a.name, type: a.t}];
			case _: [];
		};
	}

	/**
		Walks the message function's switch and records, per constructor,
		the rendered super-call argument. Plain string constants stay
		quoted; expressions render through the expression compiler with
		the case's pattern variables in scope.
	**/
	function collectMessageCases(e: TypedExpr, options: Array<haxe.macro.Type.EnumField>, out: Map<String, String>): Void {
		switch(e.expr) {
			case TReturn(r) if(r != null):
				collectMessageCases(r, options, out);
			case TBlock(stmts):
				for(s in stmts) collectMessageCases(s, options, out);
				collectCollapsedCase(stmts, options, out);
			case TMeta(_, inner):
				collectMessageCases(inner, options, out);
			case TSwitch(_, cases, _):
				for(c in cases) {
					if(c.values.length == 0) {
						continue;
					}
					final name = caseConstructorName(c.values[0], options);
					if(name == null) {
						continue;
					}
					bindPatternLocals(c.expr);
					final body = unwrapReturn(c.expr);
					switch(body.expr) {
						case TConst(TString(s)):
							out.set(name, '"' + s + '"');
						case _:
							out.set(name, expr.rawExpression(body));
					}
				}
			case _:
		}
	}

	/**
		Renames a case body's pattern captures to the payload argument
		names of their constructors, following plain local aliases. The
		typer hands captures over as generated temporaries; the emitted
		variant exposes the payload as its constructor property, whose
		name is the declaration's argument name.
	**/
	/**
		A single-case switch never survives typing: it arrives as a block
		holding the pattern capture and the case body, so the TSwitch walk
		in collectMessageCases cannot see it. Recover the constructor from
		the capture's payload extraction and the message from the trailing
		return.
	**/
	function collectCollapsedCase(stmts: Array<TypedExpr>, options: Array<haxe.macro.Type.EnumField>, out: Map<String, String>): Void {
		if(stmts.length != 2) {
			return;
		}
		switch(stmts[0].expr) {
			case TVar(_, init) if(init != null):
				switch(stripDecorations(init).expr) {
					case TEnumParameter(_, ef, _):
						final name = ef.name;
						for(o in options) {
							if(o.name != name) {
								continue;
							}
							bindPatternLocals(stmts[0]);
							bindPatternLocals(stmts[1]);
							final body = unwrapReturn(stmts[1]);
							switch(body.expr) {
								case TConst(TString(s)):
									out.set(name, '"' + s + '"');
								case _:
									out.set(name, expr.rawExpression(body));
							}
						}
					case _:
				}
			case _:
		}
	}

	function bindPatternLocals(e: TypedExpr): Void {
		switch(e.expr) {
			case TBlock(stmts):
				for(s in stmts) bindPatternLocals(s);
			case TVar(v, init) if(init != null):
				switch(stripDecorations(init).expr) {
					case TEnumParameter(_, ef, index):
						expr.bindLocalName(v, expr.payloadName(ef, index));
					case TLocal(source):
						final bound = expr.boundNameOf(source);
						if(bound != null) {
							expr.bindLocalName(v, bound);
						}
					case _:
				}
			case _:
		}
	}

	function stripDecorations(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripDecorations(inner);
			case _: e;
		}
	}

	function caseConstructorName(value: TypedExpr, options: Array<haxe.macro.Type.EnumField>): Null<String> {
		switch(value.expr) {
			// Enum switches lower to a switch on the constructor index;
			// the payload enum's own constructs carry the index mapping.
			case TConst(TInt(index)):
				for(o in options) {
					if(o.index == index) {
						return o.name;
					}
				}
				return null;
			case TField(_, FEnum(_, ef)):
				return ef.name;
			case TEnumParameter(_, ef, _):
				return ef.name;
			case _:
				return null;
		}
	}

	function unwrapReturn(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TReturn(r) if(r != null): unwrapReturn(r);
			case TBlock(stmts) if(stmts.length > 0):
				// Leading pattern-variable bindings drop out: inside the
				// emitted variant the payload name is the constructor
				// property, so the rendered body refers to it directly.
				unwrapReturn(stmts[stmts.length - 1]);
			case _: e;
		}
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
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			final elems = DataTableHelper.getDataTableElements(field.expr());
			if(elems != null) {
				final formatted = [for(x in elems) (x >= 0 && x <= 9) ? Std.string(x) : "0x" + StringTools.hex(x).toLowerCase()];
				final chunks: Array<String> = [];
				var i = 0;
				while(i < formatted.length) {
					final end = Std.int(Math.min(i + 8, formatted.length));
					chunks.push("        " + formatted.slice(i, end).join(", "));
					i = end;
				}
				return [
					'    val ${field.name} = intArrayOf(\n' + chunks.join(",\n") + '\n    )'
				];
			}
		}
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
				// Uninitialized fields carry the platform default: numeric
				// types zero, buffer types a fresh empty instance.
				switch(field.type) {
					case TAbstract(a, _) if(a.get().name == "Int"):
						initStr = " = 0";
					case TInst(c, _) if(isModuleType(c.get(), "haxe.io", "BytesBuffer")):
						imports.requireType(c.get().module, "BytesBuffer");
						initStr = " = BytesBuffer()";
					case _:
				}
			case _:
		}
		return ['    ${vis}${kw} ${field.name}: ${types.of(field.type)}$initStr'];
	}

	function isModuleType(cls: ClassType, packDot: String, name: String): Bool {
		return cls.pack.join(".") == packDot && cls.name == name;
	}

	function isInterfaceMethod(cls: ClassType, f: ClassFuncData): Bool {
		for(iface in cls.interfaces) {
			final ifaceCls = iface.t.get();
			for(field in ifaceCls.fields.get()) {
				if(field.name == f.field.name) return true;
			}
		}
		return false;
	}

	function funcDecl(cls: ClassType, f: ClassFuncData, isObject: Bool): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
		}
		final args = [for(a in f.args) '${a.name}: ${types.of(a.type)}'].join(", ");
		final retType = types.of(f.ret);
		final ret = retType == "Unit" ? "" : ": " + retType;
		final vis = f.field.isPublic ? "" : "private ";
		final overrideStr = isInterfaceMethod(cls, f) ? "override " : "";
		final head = '    ${vis}${overrideStr}fun ${f.field.name}($args)$ret {';

		final boundary = switch(f.ret) {
			case TAbstract(a, _):
				final abs = a.get();
				abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
			case _: false;
		};
		expr.setDecodeBoundary(boundary);
		final body = expr.functionBody(cls, f);
		expr.setDecodeBoundary(false);

		return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
	}

	public function testFuncDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		final id = cls.module + "." + f.field.name;
		var desc: Null<String> = null;
		for(entry in f.field.meta.extract(":test")) {
			if(entry.params != null && entry.params.length > 0) {
				switch(entry.params[0].expr) {
					case EConst(CString(s)): desc = s;
					case _:
				}
			}
		}
		final runnerName = desc != null ? id + ": " + desc : id;
		final runtimePackage = RuntimeConfig.requireImportName("test module " + cls.module);
		imports.require(runtimePackage + ".test.Test");
		final body = expr.functionBody(cls, f);
		final indented = body.map(l -> "            " + l);
		return [
			"    @kotlin.test.Test",
			'    fun ${f.field.name}() {',
			'        Test.run("${escapeKotlinString(id)}", "${escapeKotlinString(runnerName)}") {',
		].concat(indented).concat([
			"        }",
			"    }"
		]);
	}

	static function escapeKotlinString(s: String): String {
		final out = new StringBuf();
		for(i in 0...s.length) {
			final c = s.charAt(i);
			if(c == '"') out.add('\\"');
			else if(c == "\\") out.add("\\\\");
			else if(c == "\n") out.add("\\n");
			else if(c == "\r") out.add("\\r");
			else if(c == "\t") out.add("\\t");
			else if(c == "$") out.add("\\$");
			else out.add(c);
		}
		return out.toString();
	}

	// ------------------------------------------------------------------
	// Enums (stdlib/03)
	// ------------------------------------------------------------------

	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		final sorted = options.copy();
		sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
		final lines = ['sealed interface ${en.name} {'];
		for(o in sorted) {
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
				final fields = anonRef.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				final fieldLines = [for(field in fields) '    val ${field.name}: ${types.of(field.type)}'];
				final dataClassStr = ['data class ${def.name}(', fieldLines.join(",\n"), ')'].join("\n");

				if(isStructKeyCandidate(fields)) {
					final cmpLines = [
						'fun compare(a: ${def.name}, b: ${def.name}): Int {',
						'    if (a === b) return 0',
						'    var cmp = 0'
					];
					for(f in fields) {
						switch(Context.follow(f.type)) {
							case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Bool"):
								cmpLines.push('    cmp = a.${f.name}.compareTo(b.${f.name})');
								cmpLines.push('    if (cmp != 0) return cmp');
							case TInst(c, _) if(c.get().name == "String"):
								cmpLines.push('    cmp = a.${f.name}.compareTo(b.${f.name})');
								cmpLines.push('    if (cmp != 0) return cmp');
							case _:
								switch(f.type) {
									case TType(innerDef, _):
										imports.requireType(innerDef.get().module, "compare");
										cmpLines.push('    cmp = compare(a.${f.name}, b.${f.name})');
										cmpLines.push('    if (cmp != 0) return cmp');
									case _:
								}
						}
					}
					cmpLines.push('    return 0');
					cmpLines.push('}');
					return dataClassStr + "\n\n" + cmpLines.join("\n");
				}

				return dataClassStr;
			case TType(_, _):
				// An alias typedef lowers to a platform alias of the
				// underlying named type.
				return 'typealias ${def.name} = ${types.of(def.type)}';
			case _:
				return null;
		}
	}

	function isStructKeyCandidate(fields: Array<ClassField>): Bool {
		for(f in fields) {
			if(!isFieldKeyCandidate(f.type)) return false;
		}
		return true;
	}

	function isFieldKeyCandidate(t: Type): Bool {
		return switch(t) {
			case TAbstract(a, _):
				final n = a.get().name;
				n == "Int" || n == "Bool";
			case TInst(c, _):
				c.get().name == "String";
			case TType(d, _):
				switch(d.get().type) {
					case TAnonymous(anon):
						isStructKeyCandidate(anon.get().fields);
					case _: false;
				}
			case TLazy(fn):
				isFieldKeyCandidate(fn());
			case _: false;
		};
	}
}
#end
