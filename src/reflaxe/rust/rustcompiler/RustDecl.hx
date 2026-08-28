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
		if(cls.isInterface) {
			final lines: Array<String> = [];
			lines.push("pub trait " + cls.name + " {");
			for(f in funcFields) {
				final paramList = [for(a in f.args) RustImports.toSnakeCase(a.name) + ": " + types.of(a.type, true)].join(", ");
				final selfPrefix = f.isStatic ? "" : "&self" + (f.args.length > 0 ? ", " : "");
				final retType = types.of(f.ret, false);
				final ret = retType == "()" ? "" : " -> " + retType;
				lines.push('    fn ${RustImports.toSnakeCase(f.field.name)}($selfPrefix$paramList)$ret;');
			}
			lines.push("}");
			return lines.join("\n");
		}

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
			if(f.isStatic) {
				for(l in staticFuncDecl(cls, f)) lines.push(l);
			} else {
				for(l in instanceFuncDecl(cls, f, hasLifetime)) lines.push(l);
			}
		}
		lines.push("}");

		for(iface in cls.interfaces) {
			final ifaceCls = iface.t.get();
			lines.push("\nimpl" + ltParam + " " + ifaceCls.name + " for " + cls.name + ltParam + " {");
			var ifaceSep = false;
			for(f in funcFields) {
				if(f.field.name == "new") continue;
				var inIface = false;
				for(ifField in ifaceCls.fields.get()) {
					if(ifField.name == f.field.name) {
						inIface = true;
						break;
					}
				}
				if(inIface) {
					if(ifaceSep) lines.push("");
					ifaceSep = true;
					for(l in instanceFuncDecl(cls, f, hasLifetime, true)) lines.push(l);
				}
			}
			lines.push("}");
		}

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
				final params = [for(arg in args) RustImports.toSnakeCase(arg.name) + ": " + fieldType(arg.type, arg.name)].join(", ");
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

	function fieldType(t: Type, name: String): String {
		return switch(t) {
			case TAbstract(a, _) if(a.get().name == "Int"):
				// Byte-position payloads index Rust slices and stay usize; every
				// other Int payload keeps the shared Int mapping.
				(name == "remaining" || name == "consumed") ? "usize" : types.of(t);
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
							out.set(name, renderDisplayFormat(body));
					}
				}
			case _:
		}
	}

	/**
		A single-case switch in statement position collapses into a two
		statement block after typing: the payload binding and the body. Recover
		the case so Display keeps its message.
	**/
	function collectCollapsedCase(stmts: Array<TypedExpr>, options: Array<haxe.macro.Type.EnumField>, out: Map<String, String>): Void {
		if(stmts.length != 2) {
			return;
		}
		switch(stmts[0].expr) {
			case TVar(_, init) if(init != null):
				switch(stripDecorations(init).expr) {
					case TEnumParameter(_, ef, _):
					for(o in options) {
						if(o.name != ef.name) {
							continue;
						}
						bindPatternLocals(stmts[0]);
						bindPatternLocals(stmts[1]);
						final body = unwrapReturn(stmts[1]);
						switch(body.expr) {
							case TConst(TString(s)):
								out.set(o.name, '"' + s + '"');
							case _:
								out.set(o.name, renderDisplayFormat(body));
						}
						}
				case _:
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
		final errOwner = isFallible ? resolveErrorOwner(f, cls) : null;
		if(isFallible && errOwner != null) {
			imports.requireType(errOwner.module, errOwner.name);
		}
		expr.setFallible(isFallible, errOwner != null ? errOwner.name : null, errOwner != null && errOwner.hasOverflow ? state.overflowVariant : null);

		final rawRetType = returnsArgArray(f) ? types.of(f.ret, true) : types.of(f.ret, false);
		final retType = isFallible ? 'Result<$rawRetType, ${errOwner.name}>' : rawRetType;
		final ret = retType == "()" ? "" : " -> " + retType;
		final vis = f.field.isPublic ? "pub " : "";
		final head = '    ${vis}fn ${snakeName}($args)$ret {';

		expr.setReturnUnsigned(rawRetType == "u32");
		final body = expr.functionBody(cls, f);
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

	/**
		Resolves the error enum owning this function's Result from what the body
		actually throws. The global names stay as the fallback for functions
		that are fallible only through helper calls.
	**/
	function resolveErrorOwner(f: ClassFuncData, cls: ClassType): {name: String, module: String, hasOverflow: Bool} {
		final key = RustEmissionState.funcKey(f.classType.module, f.field.name, f.isStatic);
		if(state.funcEnumConflicts.exists(key)) {
			Context.error("call paths reach two different error enums"
				+ "; the Rust lowering supports one error enum per function", f.field.pos);
		}
		var unique:Null<{name: String, module: String}> = null;
		for(thrown in collectThrownPayloadEnums(f.expr)) {
			if(unique == null) {
				unique = thrown;
			} else if(unique.module != thrown.module) {
					Context.error("function throws payloads of " + unique.module + " and " + thrown.module
					+ "; the Rust lowering supports one error enum per function", f.field.pos);
				}
		}
		if(unique == null) {
			// No direct throw: the error enum arrived through a call edge.
			final inherited = state.funcErrorEnums.get(key);
			if(inherited != null) {
				unique = inherited;
			}
		}
		if(unique != null) {
				final emittedIn = state.payloadEnumModules.exists(unique.module) ? state.payloadEnumModules.get(unique.module) : cls.module;
				return {
					name: unique.name,
					module: emittedIn,
					hasOverflow: state.countOverflowEnums.exists(unique.module)
				};
			}
		return {
				name: findErrorOwner(),
				module: state.errorModule != null ? state.errorModule : cls.module,
				hasOverflow: true
			};
	}

	function collectThrownPayloadEnums(e: TypedExpr): Array<{name: String, module: String}> {
		final out: Array<{name: String, module: String}> = [];
		if(e == null) {
			return out;
		}
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TThrow(t):
					switch(stripDecorations(t).expr) {
						case TNew(c, _, args) if(args.length > 0):
							final en = payloadEnumOfArg(args[0]);
							if(en != null && state.exceptionPayloads.exists(c.get().module)) {
								out.push({name: en.get().name, module: en.get().module});
							}
						case _:
					}
				case _:
			}
			haxe.macro.TypedExprTools.iter(x, walk);
		}
		walk(e);
		return out;
	}

	function payloadEnumOfArg(arg: TypedExpr): Null<Ref<haxe.macro.Type.EnumType>> {
		return switch(stripDecorations(arg).expr) {
			case TField(_, FEnum(en, _)): en;
			case TCall(fn, _):
				switch(stripDecorations(fn).expr) {
					case TField(_, FEnum(en, _)): en;
						case _: null;
					}
			case _: null;
		};
	}

	function instanceFuncDecl(cls: ClassType, f: ClassFuncData, hasLifetime: Bool, isTraitImpl: Bool = false): Array<String> {
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
		final errOwner = isFallible ? resolveErrorOwner(f, cls) : null;
		if(isFallible && errOwner != null) {
			imports.requireType(errOwner.module, errOwner.name);
		}
		expr.setFallible(isFallible, errOwner != null ? errOwner.name : null, errOwner != null && errOwner.hasOverflow ? state.overflowVariant : null);

		final rawRetType = methodReturnType(f.ret, f.field.name);
		final retType = isFallible ? 'Result<$rawRetType, ${errOwner.name}>' : rawRetType;
		final ret = retType == "()" ? "" : " -> " + retType;
		final vis = (f.field.isPublic && !isTraitImpl) ? "pub " : "";
		final head = '    ${vis}fn ${snakeName}($allArgs)$ret {';

		expr.setReturnUnsigned(rawRetType == "u32");
		final body = expr.functionBody(cls, f);
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
		// The preScan fixpoint owns fallibility: direct throws, runtime-shim
		// calls, and inheritance through call edges all land in the registry.
		if(state.funcErrorEnums.exists(RustEmissionState.funcKey(f.classType.module, f.field.name, f.isStatic))) {
			return true;
		}
		if(f.field.name == "encode" && f.args.length == 1) {
			return true;
		}
		// Local re-check of direct fallibility on the body as emitted; the
		// registry cannot fall behind this without a compile error following.
		var throwsOrCallsFallible = false;
		function walk(e: TypedExpr) {
			switch(e.expr) {
				case TThrow(_):
					throwsOrCallsFallible = true;
				case TCall(fn, _):
					switch(fn.expr) {
						case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
							if(RustEmissionState.runtimeShimIsFallible(cf.get().name)) {
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
		// Tests are the error boundary: a fault inside one is a recorded
		// failure, so the body lowers as infallible and fallible callees
		// unwrap through the catch_unwind harness.
		expr.setFallible(false);
		final body = expr.functionBody(cls, f);
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
				final deriveAttr = isAllCopy(fields) ? "#[derive(Debug, Clone, Copy, PartialEq)]" : "#[derive(Debug, Clone, PartialEq)]";
				final structStr = [
					deriveAttr,
					'pub struct ${def.name} {',
					fieldLines.join("\n"),
					"}"
				].join("\n");

				if(isStructKeyCandidate(fields)) {
					final fnName = "compare_" + RustImports.toSnakeCase(def.name);
					final cmpLines = [
						'pub fn $fnName(a: &${def.name}, b: &${def.name}) -> std::cmp::Ordering {'
					];
					for(f in fields) {
						final fieldSnake = RustImports.toSnakeCase(f.name);
						switch(Context.follow(f.type)) {
							case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Bool"):
								cmpLines.push('    let cmp_$fieldSnake = a.$fieldSnake.cmp(&b.$fieldSnake);');
								cmpLines.push('    if cmp_$fieldSnake != std::cmp::Ordering::Equal { return cmp_$fieldSnake; }');
							case TInst(c, _) if(c.get().name == "String"):
								state.shimsUsed.set("std.SortedMap", true);
								cmpLines.push('    let cmp_$fieldSnake = crate::runtime::sorted_map::compare_utf16_code_units(a.$fieldSnake.as_str(), b.$fieldSnake.as_str());');
								cmpLines.push('    if cmp_$fieldSnake != std::cmp::Ordering::Equal { return cmp_$fieldSnake; }');
							case _:
								switch(f.type) {
									case TType(innerDef, _):
										final innerCmp = "compare_" + RustImports.toSnakeCase(innerDef.get().name);
										imports.requireType(innerDef.get().module, innerCmp);
										cmpLines.push('    let cmp_$fieldSnake = $innerCmp(&a.$fieldSnake, &b.$fieldSnake);');
										cmpLines.push('    if cmp_$fieldSnake != std::cmp::Ordering::Equal { return cmp_$fieldSnake; }');
									case _:
								}
						}
					}
					cmpLines.push('    std::cmp::Ordering::Equal');
					cmpLines.push('}');
					return structStr + "\n\n" + cmpLines.join("\n");
				}

				return structStr;
			case TType(_, _):
				return 'pub type ${def.name} = ${types.of(def.type)};';
			case _:
				return null;
		}
	}

	function isAllCopy(fields: Array<ClassField>): Bool {
		for(f in fields) {
			if(!isTypeCopy(f.type)) return false;
		}
		return true;
	}

	function isTypeCopy(t: Type): Bool {
		return switch(t) {
			case TAbstract(a, _):
				final n = a.get().name;
				n == "Int" || n == "Bool" || n == "Float";
			case TType(d, _):
				switch(d.get().type) {
					case TAnonymous(anon):
						isAllCopy(anon.get().fields);
					case _: false;
				}
			case TLazy(fn):
				isTypeCopy(fn());
			case _: false;
		};
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
