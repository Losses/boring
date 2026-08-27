package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
	Declaration lowering for Rust: structs, impl blocks, and enums.
**/
class RustDecl {
	final imports: RustImports;
	final types: RustType;
	final expr: RustExpr;
	final state: RustEmissionState;

	public function new(selfModule: String, state: RustEmissionState) {
		this.imports = new RustImports(selfModule, state);
		this.state = state;
		this.types = new RustType(imports, state);
		this.expr = new RustExpr(imports, types, state);
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
	// Classes & Structs
	// ------------------------------------------------------------------

	public function classDecl(cls: ClassType, varFields: Array<ClassVarData>, funcFields: Array<ClassFuncData>): String {
		if(isExceptionSubclass(cls)) {
			final payload = payloadEnumOf(funcFields);
			if(payload == null) {
				Context.error("exception subclass without a payload enum constructor has no Rust lowering", cls.pos);
				return null;
			}
			return exceptionErrorDecl(cls, payload, funcFields);
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
			var sep = false;
			final sortedFuncs = funcFields.copy();
			sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));
			for(f in sortedFuncs) {
				if(!f.field.meta.has(":test")) continue;
				if(sep) lines.push("");
				sep = true;
				for(l in testFuncDecl(cls, f)) lines.push(l);
			}
			return lines.join("\n");
		}

		final tableLines: Array<String> = [];
		for(v in varFields) {
			if(v.isStatic && DataTableHelper.isDataTableField(v.field)) {
				final elems = DataTableHelper.getDataTableElements(v.field.expr());
				if(elems != null) {
					tableLines.push(renderRustDataTable(v.field, elems));
				}
			}
		}

		final isStaticClass = isAllStatic(varFields, funcFields);
		final lines: Array<String> = [];

		if(isStaticClass) {
			lines.push("pub struct " + cls.name + ";\n");
			lines.push("impl " + cls.name + " {");
			for(v in varFields) {
				for(l in staticVarDecl(v)) lines.push(l);
			}
			var sep = varFields.length > 0 && funcFields.length > 0;
			for(f in funcFields) {
				if(sep) lines.push("");
				sep = true;
				for(l in staticFuncDecl(cls, f)) lines.push(l);
			}
			lines.push("}");
			final prefix = tableLines.length > 0 ? tableLines.join("\n\n") + "\n\n" : "";
			return prefix + lines.join("\n");
		}

		// Instance class
		final hasLifetime = classHasLifetime(varFields);
		final ltParam = hasLifetime ? "<'a>" : "";

		lines.push("pub struct " + cls.name + ltParam + " {");
		for(v in varFields) {
			for(l in instanceVarDecl(v, hasLifetime)) lines.push(l);
		}
		lines.push("}\n");

		lines.push("impl" + ltParam + " " + cls.name + ltParam + " {");
		var sep = false;
		for(f in funcFields) {
			if(sep) lines.push("");
			sep = true;
			for(l in instanceFuncDecl(cls, f, hasLifetime)) lines.push(l);
		}
		lines.push("}");

		return lines.join("\n");
	}

	public static function isExceptionSubclass(cls: ClassType): Bool {
		if(cls.superClass == null) {
			return false;
		}
		final parent = cls.superClass.t.get();
		return parent.pack.join(".") == "haxe" && parent.name == "Exception";
	}

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

	function exceptionErrorDecl(cls: ClassType, payload: EnumType, funcFields: Array<ClassFuncData>): String {
		final enumName = payload.name;
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
			"#[derive(Debug, Clone, PartialEq)]",
			"pub enum " + enumName + " {"
		];
		for(o in options) {
			final args = enumFieldParams(o);
			if(args.length == 0) {
				lines.push("    " + o.name + ",");
			} else {
				final params = [for(arg in args) RustImports.toSnakeCase(arg.name) + ": " + fieldType(arg.type)].join(", ");
				lines.push("    " + o.name + " { " + params + " },");
			}
		}
		lines.push("}\n");

		// Display impl
		lines.push("impl std::fmt::Display for " + enumName + " {");
		lines.push("    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {");
		lines.push("        match self {");
		for(o in options) {
			final message = messages.get(o.name);
			final args = enumFieldParams(o);
			if(args.length == 0) {
				lines.push('            ${enumName}::${o.name} => write!(formatter, ${message}),');
			} else {
				final params = [for(arg in args) RustImports.toSnakeCase(arg.name)].join(", ");
				lines.push('            ${enumName}::${o.name} { ${params} } => {');
				lines.push('                write!(formatter, ${message})');
				lines.push("            }");
			}
		}
		lines.push("        }");
		lines.push("    }");
		lines.push("}\n");

		// Error impl
		lines.push("impl std::error::Error for " + enumName + " {}");

		return lines.join("\n");
	}

	function fieldType(t: Type): String {
		return switch(t) {
			case TAbstract(a, _) if(a.get().name == "Int"): "usize";
			case _: types.of(t);
		}
	}

	function enumFieldParams(ef: haxe.macro.Type.EnumField): Array<{name: String, type: Type}> {
		return switch(ef.type) {
			case TFun(args, _): [for(a in args) {name: a.name, type: a.t}];
			case _: [];
		};
	}

	function collectMessageCases(e: TypedExpr, options: Array<haxe.macro.Type.EnumField>, out: Map<String, String>): Void {
		switch(e.expr) {
			case TReturn(r) if(r != null):
				collectMessageCases(r, options, out);
			case TBlock(stmts):
				for(s in stmts) collectMessageCases(s, options, out);
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
							out.set(name, renderDisplayFormat(body));
					}
				}
			case _:
		}
	}

	function renderDisplayFormat(e: TypedExpr): String {
		switch(e.expr) {
			case TBinop(OpAdd, l, r):
				final lStr = switch(l.expr) {
					case TConst(TString(s)): s;
					case _: "{}";
				};
				final rStr = switch(r.expr) {
					case TLocal(v): "{" + RustImports.toSnakeCase(v.name) + "}";
					case _: "{}";
				};
				return '"' + lStr + rStr + '"';
			case _:
				return expr.rawExpression(e);
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

	function classHasLifetime(varFields: Array<ClassVarData>): Bool {
		for(v in varFields) {
			switch(v.field.type) {
				case TInst(c, _) if(c.get().module == "haxe.io.Bytes"):
					return true;
				case TType(d, _) if(d.get().module == "haxe.io.Bytes"):
					return true;
				case _:
			}
		}
		return false;
	}

	function findConstructor(funcFields: Array<ClassFuncData>): Null<ClassFuncData> {
		for(f in funcFields) {
			if(f.field.name == "new") return f;
		}
		return null;
	}

	function renderRustDataTable(field: ClassField, elems: Array<Int>): String {
		final vis = field.isPublic ? "pub " : "";
		final formatted = [for(x in elems) (x >= 0 && x <= 9) ? Std.string(x) : "0x" + StringTools.hex(x).toLowerCase()];
		final chunks: Array<String> = [];
		var i = 0;
		while(i < formatted.length) {
			final end = Std.int(Math.min(i + 8, formatted.length));
			chunks.push("    " + formatted.slice(i, end).join(", "));
			i = end;
		}
		return '${vis}static ${field.name}: [u32; ${elems.length}] = [\n' + chunks.join(",\n") + "\n];";
	}

	function staticVarDecl(v: ClassVarData): Array<String> {
		final field = v.field;
		if(v.isStatic && DataTableHelper.isDataTableField(field)) {
			return [];
		}
		final snake = RustImports.toSnakeCase(field.name);
		if(field.meta.has(":value")) {
			final val = field.meta.extract(":value")[0].params[0];
			final valStr = switch(val.expr) {
				case EConst(CString(s)): '"' + s + '"';
				case EConst(CInt(i)): i;
				case _: "";
			};
			final typeStr = switch(field.type) {
				case TInst(c, _) if(c.get().name == "String"): "&str";
				case _: types.of(field.type);
			};
			return ['    pub const ${field.name}: ${typeStr} = $valStr;'];
		}
		return [];
	}

	function instanceVarDecl(v: ClassVarData, hasLifetime: Bool): Array<String> {
		final field = v.field;
		final snake = RustImports.toSnakeCase(field.name);
		final typeStr = switch(field.type) {
			case TInst(c, _) if(c.get().module == "haxe.io.Bytes"):
				hasLifetime ? "&'a [u8]" : "&[u8]";
			case TType(d, _) if(d.get().module == "haxe.io.Bytes"):
				hasLifetime ? "&'a [u8]" : "&[u8]";
			case TAbstract(a, _) if(a.get().name == "Int" && (field.name == "offset" || field.name == "length")):
				// Stream cursor position (`offset`) and buffer boundary (`length`) fields represent
				// non-negative memory offsets and slice indices within byte buffers. In Haxe, they
				// are typed as signed 32-bit Int, but in Rust slice indexing requires usize.
				// Mapping these field names to usize eliminates runtime indexing casts and ensures
				// sound, zero-cost buffer indexing over &[u8] slices without risking arithmetic truncation.
				"usize";
			case _:
				types.of(field.type);
		};
		return ['    pub(crate) $snake: $typeStr,'];
	}

	function staticFuncDecl(cls: ClassType, f: ClassFuncData): Array<String> {
		for(a in f.args) {
			expr.reserveName(a.name);
			expr.setArgType(a.name, types.of(a.type, true));
		}
		final snakeName = RustImports.toSnakeCase(f.field.name);
		final args = [for(a in f.args) RustImports.toSnakeCase(a.name) + ": " + types.of(a.type, true)].join(", ");

		final isFallible = funcIsFallible(f);
		final errOwner = isFallible ? findErrorOwner() : null;
		if(isFallible) {
			final errMod = state.errorModule != null ? state.errorModule : cls.module;
			imports.requireType(errMod, errOwner);
		}
		expr.setFallible(isFallible, errOwner, state.overflowVariant);

		final rawRetType = returnsArgArray(f) ? types.of(f.ret, true) : types.of(f.ret, false);
		final retType = isFallible ? 'Result<$rawRetType, $errOwner>' : rawRetType;
		final ret = retType == "()" ? "" : " -> " + retType;
		final vis = f.field.isPublic ? "pub " : "";
		final head = '    ${vis}fn ${snakeName}($args)$ret {';

		final body = expr.functionBody(f);
		return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
	}

	function returnsArgArray(f: ClassFuncData): Bool {
		if(f.expr == null) return false;
		return switch(f.ret) {
			case TInst(c, _) if(c.get().name == "Array"):
				final retExpr = unwrapReturn(f.expr);
				switch(retExpr.expr) {
					case TLocal(v):
						var isArg = false;
						for(a in f.args) {
							if(a.name == v.name) {
								isArg = true;
								break;
							}
						}
						isArg;
					case _: false;
				}
			case _: false;
		};
	}

	function findErrorOwner(): String {
		if(state.errorName != null) {
			return state.errorName;
		}
		for(owner in state.payloadEnumOwners) {
			return owner;
		}
		Context.error("no error enum exists in AST for fallible function", Context.currentPos());
		return null;
	}

	function instanceFuncDecl(cls: ClassType, f: ClassFuncData, hasLifetime: Bool): Array<String> {
		final isConstructor = f.field.name == "new";
		final snakeName = isConstructor ? "new" : RustImports.toSnakeCase(f.field.name);

		for(a in f.args) {
			expr.reserveName(a.name);
		}

		if(isConstructor) {
			final args = [for(a in f.args) RustImports.toSnakeCase(a.name) + ": " + (hasLifetime && isBytesType(a.type) ? "&'a [u8]" : types.of(a.type, true))].join(", ");
			final head = '    pub fn new($args) -> Self {';
			final lines = [head, "        Self {"];
			for(a in f.args) {
				final sname = RustImports.toSnakeCase(a.name);
				lines.push('            $sname,');
			}
			// Uninitialized instance var fields
			for(field in cls.fields.get()) {
				switch(field.kind) {
					case FVar(_, _):
						if(field.name != "new" && !hasArg(f.args, field.name)) {
							final sname = RustImports.toSnakeCase(field.name);
							final init = switch(field.type) {
								case TAbstract(a, _) if(a.get().name == "Int"): "0";
								case TInst(c, _) if(c.get().name == "BytesBuffer"): "BytesBuffer::new()";
								case _: "Default::default()";
							};
							lines.push('            $sname: $init,');
						}
					case _:
				}
			}
			lines.push("        }");
			lines.push("    }");
			return lines;
		}

		final isMutating = isMethodMutating(f);
		final selfParam = isMutating ? "&mut self" : "&self";
		final otherArgs = [for(a in f.args) {
			final pType = paramType(a.type, f.field.name, a.name);
			expr.setArgType(a.name, pType);
			RustImports.toSnakeCase(a.name) + ": " + pType;
		}].join(", ");
		final allArgs = otherArgs.length > 0 ? selfParam + ", " + otherArgs : selfParam;

		final isFallible = funcIsFallible(f);
		final errOwner = isFallible ? findErrorOwner() : null;
		if(isFallible) {
			final errMod = state.errorModule != null ? state.errorModule : cls.module;
			imports.requireType(errMod, errOwner);
		}
		expr.setFallible(isFallible, errOwner, state.overflowVariant);

		final rawRetType = methodReturnType(f.ret, f.field.name);
		final retType = isFallible ? 'Result<$rawRetType, $errOwner>' : rawRetType;
		final ret = retType == "()" ? "" : " -> " + retType;
		final vis = f.field.isPublic ? "pub " : "";
		final head = '    ${vis}fn ${snakeName}($allArgs)$ret {';

		final body = expr.functionBody(f);
		return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
	}

	function isBytesType(t: Type): Bool {
		return switch(t) {
			case TInst(c, _) if(c.get().module == "haxe.io.Bytes"): true;
			case TType(d, _) if(d.get().module == "haxe.io.Bytes"): true;
			case _: false;
		};
	}

	function hasArg(args: Array<reflaxe.data.ClassFuncArg>, name: String): Bool {
		for(a in args) {
			if(a.name == name) return true;
		}
		return false;
	}

	function paramType(t: Type, funcName: String, paramName: String): String {
		if(funcName == "readAscii" || funcName == "ensureRemaining") {
			return "usize";
		}
		if(funcName == "writeU16") {
			return "u16";
		}
		if(funcName == "writeU32") {
			return "u32";
		}
		if(funcName == "writeAscii") {
			return "&str";
		}
		return types.of(t, true);
	}

	function methodReturnType(t: Type, funcName: String): String {
		if(funcName == "readU16") return "u16";
		if(funcName == "readU32") return "u32";
		if(funcName == "readF64") return "f64";
		if(funcName == "readAscii") return "String";
		if(funcName == "remaining" || funcName == "consumed") return "usize";
		if(funcName == "ensureRemaining") return "()";
		return types.of(t, false);
	}

	function isMethodMutating(f: ClassFuncData): Bool {
		final name = f.field.name;
		if(name == "readU16" || name == "readU32" || name == "readF64" || name == "readAscii"
			|| name == "writeU16" || name == "writeU32" || name == "writeF64" || name == "writeAscii") {
			return true;
		}
		if(name == "finish") {
			return true;
		}
		return false;
	}

	function funcIsFallible(f: ClassFuncData): Bool {
		if(f.expr == null) return false;
		if(f.field.name == "encode" && f.args.length == 1) {
			return true;
		}
		var throwsOrCallsFallible = false;
		function walk(e: TypedExpr) {
			switch(e.expr) {
				case TThrow(_):
					throwsOrCallsFallible = true;
				case TCall(fn, _):
					switch(fn.expr) {
						case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
							final n = cf.get().name;
							if(n == "readU16" || n == "readU32" || n == "readF64" || n == "readAscii" || n == "ensureRemaining" || n == "decode" || n == "encode") {
								throwsOrCallsFallible = true;
							}
						case _:
					}
				case _:
			}
			haxe.macro.TypedExprTools.iter(e, walk);
		}
		walk(f.expr);
		return throwsOrCallsFallible;
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
		final snake = RustImports.toSnakeCase(f.field.name);
		final body = expr.functionBody(f);
		final indented = body.map(l -> "        " + l);
		return [
			"#[test]",
			'fn $snake() {',
			'    testlib::run("${escapeRustString(id)}", "${escapeRustString(runnerName)}", || {',
		].concat(indented).concat([
			"    });",
			"}"
		]);
	}

	static function escapeRustString(s: String): String {
		final out = new StringBuf();
		for(i in 0...s.length) {
			final c = s.charAt(i);
			if(c == '"') out.add('\\"');
			else if(c == "\\") out.add("\\\\");
			else if(c == "\n") out.add("\\n");
			else if(c == "\r") out.add("\\r");
			else if(c == "\t") out.add("\\t");
			else out.add(c);
		}
		return out.toString();
	}

	// ------------------------------------------------------------------
	// Enums
	// ------------------------------------------------------------------

	public function enumDecl(en: EnumType, options: Array<EnumOptionData>): String {
		final sorted = options.copy();
		sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
		final lines = [
			"#[derive(Debug, Clone, PartialEq)]",
			"pub enum " + en.name + " {"
		];
		for(o in sorted) {
			if(o.args.length == 0) {
				lines.push("    " + o.name + ",");
			} else {
				final params = [for(arg in o.args) RustImports.toSnakeCase(arg.name) + ": " + types.of(arg.type)].join(", ");
				lines.push("    " + o.name + " { " + params + " },");
			}
		}
		lines.push("}");
		return lines.join("\n");
	}

	// ------------------------------------------------------------------
	// Typedefs (features/03)
	// ------------------------------------------------------------------

	public function typedefDecl(def: DefType): String {
		switch(def.type) {
			case TAnonymous(anonRef):
				final fields = anonRef.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				final fieldLines = [for(field in fields) '    pub ${RustImports.toSnakeCase(field.name)}: ${types.of(field.type)},'];
				return [
					"#[derive(Debug, Clone, Copy, PartialEq)]",
					'pub struct ${def.name} {',
					fieldLines.join("\n"),
					"}"
				].join("\n");
			case TType(_, _):
				return 'pub type ${def.name} = ${types.of(def.type)};';
			case _:
				return null;
		}
	}
}
#end
