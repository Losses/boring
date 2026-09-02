package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import ValueTypeSupport;
import ValueTypeSupport.ValueTypeOperator;

/**
	Statement and expression lowering from the Haxe typed AST to Rust.
**/
class RustExpr {
	// Runtime shim parameters that take i32 where the haxe declaration
	// says Int. slice clamps with bounds that may be negative, so its
	// bound parameters are signed in the Rust runtime; the compiler
	// cannot read a Rust signature, so the signed positions are listed
	// here and the call sites cast into them. Resident runtime modules
	// take their signed positions from the resident ABI rule at every
	// call, so they carry no entry here.
	static final SIGNED_SHIM_PARAMS: Map<String, Array<Int>> = [
		"u_string.slice" => [1, 2]
	];

	final imports: RustImports;
	final types: RustType;
	final state: RustEmissionState;

	var isFallible: Bool = false;
	var countOverflowVariant: Null<String> = null;
	var errorTypeName: Null<String> = null;
	var returnUnsigned: Bool = false;
	var returnTypeName: Null<String> = null;
	var currentReturnType: Null<Type> = null;

	final subst: Map<Int, String> = [];
	/** Catch variables of the region being lowered; features/06 catch-site lowering. */
	final catchVars: Map<Int, Bool> = [];
	final mutated: Map<Int, Bool> = [];
	final usedNames: Map<String, Bool> = [];
	final hiddenNames: Map<Int, String> = [];
	final rangeLoopVars: Map<Int, Bool> = [];
	final argTypes: Map<String, String> = [];
	final paramVarIds: Map<Int, Bool> = [];
	final unsignedLocals: Map<Int, Bool> = [];
	final fpInt64Halves: Map<Int, Bool> = [];
	var hiddenCounter: Int = 0;

	public function new(imports: RustImports, types: RustType, state: RustEmissionState) {
		this.imports = imports;
		this.types = types;
		this.state = state;
	}

	public function setArgType(name: String, typeName: String): Void {
		argTypes.set(name, typeName);
	}

	public function setReturnUnsigned(value: Bool): Void {
		this.returnUnsigned = value;
	}

	public function setReturnTypeName(value: Null<String>): Void {
		this.returnTypeName = value;
	}

	public function setReturnType(value: Null<Type>): Void {
		this.currentReturnType = value;
	}

	public function reserveName(name: String): Void {
		usedNames.set(name, true);
	}

	public function bindLocalName(v: TVar, name: String): Void {
		subst.set(v.id, name);
	}

	public function boundNameOf(v: TVar): Null<String> {
		return subst.get(v.id);
	}

	public function setFallible(value: Bool, errorType: Null<String> = null, overflowVariant: Null<String> = null): Void {
		this.isFallible = value;
		this.errorTypeName = errorType != null ? errorType : state.errorName;
		// The overflow variant belongs to the resolved error enum; a function
		// owned by an enum without it reports the gap at the first capacity
		// expression that copies the foreign variant here.
		this.countOverflowVariant = overflowVariant;
		if(value && this.errorTypeName == null) {
			Context.error("fallible operation requires an error enum, but none found in AST", Context.currentPos());
		}
	}

	public function expressionOf(e: TypedExpr): String {
		return expr(e);
	}

	public function topLevelStatements(e: TypedExpr): String {
		scanLocals(e);
		return blockLines(statementsOf(e), 0).join("\n");
	}

	public function rawExpression(e: TypedExpr): String {
		return expr(e);
	}

	public function rawArrayLiteral(e: TypedExpr): String {
		return switch(stripWrap(e).expr) {
			case TArrayDecl(elements): "[" + [for(x in elements) expr(x)].join(", ") + "]";
			case _: rawExpression(e);
		};
	}

	/** Renders the literal itself for a Rust static function pointer initializer. */
	public function rawFunctionInitializer(e: TypedExpr): String {
		return switch(stripWrap(e).expr) {
			case TFunction(f): functionLiteral(f, e.t);
			case _: fail(e, "static function fields accept capture-free initializers only");
		}
	}

	// ------------------------------------------------------------------
	// Function bodies
	// ------------------------------------------------------------------

	var currentMethodName: Null<String> = null;
	var currentClass: Null<ClassType> = null;
	var currentLocalName: Null<String> = null;

	function coalescingSiteFor(e: TypedExpr): Null<{parameter: String, defaultExpr: TypedExpr, valueExpr: TypedExpr}> {
		if(currentClass == null || currentMethodName == null) return null;
		final site = DefaultArgExpander.coalescingSite(e);
		final value = currentLocalName != null
			? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentMethodName, currentLocalName, site == null ? "" : site.parameter)
			: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentMethodName, site == null ? "" : site.parameter);
		if(site == null || value == null) {
			return null;
		}
		return site;
	}

	/** Renders the sanctioned expression in Rust's normalization closure. */
	function coalescingDefaultText(value: DefaultArgExpander.CoalescingDefaultValue, targetType: Type): String {
		return switch(value) {
			case CInt(v): Std.string(v);
			case CFloat(s):
				final padded = s.indexOf(".") >= 0 ? s : s + ".0";
				FloatPrecision.isF32() ? padded + "f32" : padded;
			case CString(s): quoteString(s) + ".to_string()";
			case CBool(b): b ? "true" : "false";
			case CNull: "None";
			case CEmptyArray: "vec![]";
			case CEmptyMap:
				imports.require("std::collections::HashMap");
				"HashMap::new()";
			case CPositiveInfinity: FloatPrecision.isF32() ? "f32::INFINITY" : "f64::INFINITY";
			case CNegativeInfinity: FloatPrecision.isF32() ? "f32::NEG_INFINITY" : "f64::NEG_INFINITY";
			case CEnum(enumRef, enumField):
				final en = enumRef.get();
				requireEnum(en.module, en.name);
				en.name + "::" + enumField.name;
			case CParameterRead(name): RustImports.toSnakeCase(name);
			case CFieldAccess(CParameterRead(staticPath), ""): coalescingStaticFieldText(staticPath, targetType);
			case CFieldAccess(receiver, fieldName):
				fieldName == "length"
					? rustU32Length("(" + coalescingDefaultText(receiver, targetType) + ").len()")
					: coalescingDefaultText(receiver, targetType) + "." + RustImports.toSnakeCase(fieldName);
			case CMethodCall(receiver, methodName, args):
				coalescingDefaultText(receiver, targetType) + "." + rustMethodName(methodName) + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CStaticCall(fullPath, args):
				final parts = fullPath.split(".");
				parts.length > 1 ? parts[0] + "::" + RustImports.toSnakeCase(parts[1]) + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")" : RustImports.toSnakeCase(fullPath) + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CConditional(c, t, f):
				"if " + coalescingDefaultText(c, targetType) + " { " + coalescingDefaultText(t, targetType) + " } else { " + coalescingDefaultText(f, targetType) + " }";
			case CBinaryOp(op, left, right):
				coalescingDefaultText(left, targetType) + " " + opStr(op) + " " + coalescingDefaultText(right, targetType);
		};
	}

	function coalescingStaticFieldText(path:String, targetType:Type):String {
		final parts = path.split(".");
		if(parts.length < 2) return path;
		final fieldName = parts[parts.length - 1];
		final typePath = parts.slice(0, parts.length - 1).join(".");
		try {
			switch(Context.getType(typePath)) {
				case TInst(clsRef, _):
					final rendered = staticRef(clsRef.get(), fieldName);
					return isStringType(targetType) && !StringTools.endsWith(rendered, ".to_string()") ? rendered + ".to_string()" : rendered;
				default:
			}
		} catch (_:Dynamic) {}
		return path;
	}

	static function rustMethodName(name:String):String {
		return name == "toUpperCase" ? "to_uppercase" : RustImports.toSnakeCase(name);
	}

	static function opStr(op:Binop):String {
		return switch(op) {
			case OpAdd: "+";
			case OpMult: "*";
			case OpDiv: "/";
			case OpMod: "%";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpShl: "<<";
			case OpShr: ">>";
			case OpUShr: ">>";
			case OpXor: "^";
			case _: "?";
		};
	}

	public function functionBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) {
			Context.error("function field has no body to lower", f.field.pos);
		}
		DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentMethodName = f.field.name;
		currentLocalName = null;
		paramVarIds.clear();
		unsignedLocals.clear();
		mutated.clear();
		for(a in f.args) {
			if(a.tvar != null) paramVarIds.set(a.tvar.id, true);
		}
		// Fuse declaration-plus-assignment pairs before the mutation scan.
		// The typer lowers abstract-inline receiver bindings as `TVar(v,
		// null)` followed by an assignment; the fused initializer is the
		// declaration's own initialization, so the scan must not read it as
		// a reassignment.
		final fusedRoot = fuseWithin(f.expr);
		f.expr.expr = fusedRoot.expr;
		scanLocals(f.expr);
		final lines = blockLines(statementsOf(f.expr), 1, true);
		return coalescingNormalizationLines(f.expr, 1, [for(a in f.args) a.name]).concat(lines);
	}

	/** Body lowering for a member declared on a value wrapper. */
	public function valueTypeFunctionBody(cls: ClassType, f: ClassFuncData, receiverName: String): Array<String> {
		final abs = ValueTypeSupport.markedAbstractOfClass(cls);
		final op = abs == null ? null : ValueTypeSupport.operatorOf(abs, f.field);
		if(op != null) {
			switch(op) {
				case Binary(_):
					if(f.args.length > 0) bindLocalName(f.args[0].tvar, "self.0");
					if(f.args.length > 1) bindLocalName(f.args[1].tvar, "rhs.0");
				case Unary(_):
					if(f.args.length > 0) bindLocalName(f.args[0].tvar, "self.0");
			}
		} else if(ValueTypeSupport.hasReceiver(f.field) && f.args.length > 0) {
			bindLocalName(f.args[0].tvar, receiverName);
		}
		final rawReturn = types.of(f.ret, false);
		setReturnUnsigned(rawReturn == "u32");
		setReturnTypeName(rawReturn);
		return functionBody(cls, f);
	}

	/** Drops Haxe's synthetic representation assignment from a validating constructor. */
	public function valueTypeConstructorBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) Context.error("value type constructor has no body to lower", f.field.pos);
		DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentMethodName = f.field.name;
		currentLocalName = null;
		paramVarIds.clear();
		unsignedLocals.clear();
		mutated.clear();
		for(a in f.args) if(a.tvar != null) paramVarIds.set(a.tvar.id, true);
		scanLocals(f.expr);
		final out:Array<String> = [];
		for(stmt in statementsOf(f.expr)) {
			if(ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt)) continue;
			for(line in stmtLines(stmt, 1)) out.push(line);
		}
		return out;
	}

	/**
		Constructor body classification (feature spec 27): a `this.f = f`
		assignment of a constructor parameter is the struct-literal
		shorthand and drops out; an assignment to a field the constructor
		does not receive as a parameter is that field's initialization in
		the literal; every other statement keeps statement form and
		renders before the literal, so constructor validation survives on
		this target.
	**/
	public function constructorBody(cls: ClassType, f: ClassFuncData): {statementLines: Array<String>, fieldInits: Map<String, String>} {
		if(f.expr == null) {
			Context.error("constructor has no body to lower", f.field.pos);
		}
		DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentMethodName = f.field.name;
		currentLocalName = null;
		paramVarIds.clear();
		unsignedLocals.clear();
		mutated.clear();
		for(a in f.args) {
			if(a.tvar != null) paramVarIds.set(a.tvar.id, true);
		}
		final fusedRoot = fuseWithin(f.expr);
		f.expr.expr = fusedRoot.expr;
		scanLocals(f.expr);
		final argNames = [for(a in f.args) a.name];
		final fieldInits = new Map<String, String>();
		final stmts: Array<TypedExpr> = [];
		for(stmt in statementsOf(f.expr)) {
			switch(stmt.expr) {
				case TBinop(OpAssign, target, value):
					switch(stripWrap(target).expr) {
						case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
							final fieldName = cf.get().name;
							final coalescing = coalescingSiteFor(value);
							if(coalescing != null) {
								continue;
							}
							final isParam = switch(stripWrap(value).expr) {
								case TLocal(v): argNames.indexOf(v.name) >= 0;
								case _: false;
							};
							if(!isParam) {
								fieldInits.set(fieldName, renderValueForType(cf.get().type, value, expr(value)));
							}
						case _:
							stmts.push(stmt);
					}
				case _:
					stmts.push(stmt);
			}
		}
		// tailScope stays off: the constructor's tail is the Ok(Self { ... })
		// literal assembled by the caller, so blockLines must not append the
		// fallible void closer `Ok(())` after the validation statements.
		final lines = stmts.length > 0 ? blockLines(stmts, 1, false) : [];
		final normalized = coalescingNormalizationLines(f.expr, 1, [for(a in f.args) a.name]);
		return {statementLines: normalized.concat(lines), fieldInits: fieldInits};
	}

	function coalescingNormalizationLines(root: TypedExpr, depth: Int, parameterOrder: Null<Array<String>> = null): Array<String> {
		final out: Array<String> = [];
		if(currentClass == null || currentMethodName == null) return out;
		final sites = DefaultArgExpander.coalescingSitesForFunction(root);
		if(parameterOrder != null) {
			var next = 0;
			for(parameterName in parameterOrder) {
				var found = next;
				while(found < sites.length && sites[found].parameter != parameterName) {
					found++;
				}
				if(found < sites.length) {
					final site = sites[found];
					sites[found] = sites[next];
					sites[next] = site;
					next++;
				}
			}
		}
		final seen: Map<String, Bool> = [];
		for(site in sites) {
			final value = currentLocalName != null
				? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentMethodName, currentLocalName, site.parameter)
				: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentMethodName, site.parameter);
			if(seen.exists(site.parameter) || value == null) {
				continue;
			}
			seen.set(site.parameter, true);
			final rawDefaultText = coalescingDefaultText(value, DefaultArgExpander.withoutNull(site.valueExpr.t));
			// When a string parameter read appears inside unwrap_or_else, Rust needs
			// the owned form (&str → String).
			final isStringDefault = switch(value) {
				case CParameterRead(_): isStringType(DefaultArgExpander.withoutNull(site.valueExpr.t));
				default: false;
			};
			final defaultText = isStringDefault ? rawDefaultText + ".to_string()" : rawDefaultText;
			out.push(indent(depth) + "let " + RustImports.toSnakeCase(site.parameter) + " = " + RustImports.toSnakeCase(site.parameter) + ".unwrap_or_else(|| " + defaultText + ");");
		}
		return out;
	}

	// ------------------------------------------------------------------
	// Statements
	// ------------------------------------------------------------------

	public function statementsOf(e: TypedExpr): Array<TypedExpr> {
		return switch(e.expr) {
			case TBlock(stmts): stmts;
			case _: [e];
		}
	}

	function stmtLines(e: TypedExpr, depth: Int): Array<String> {
		switch(e.expr) {
			case TVar(v, init) if(isTryRegion(init)):
				return regionInitializerLines(v, stripWrap(init), depth);
			case TVar(v, init) if(init != null):
				final kw = mutated.exists(v.id) ? "let mut" : "let";
				final name = RustImports.toSnakeCase(localName(v));
				final explicitType = if(isFunctionType(v.t)) {
					": " + types.functionReturnOf(v.t);
				} else switch(v.t) {
					case TInst(c, _) if(c.get().name == "SortedMapBuilder" || c.get().name == "SortedMap" || c.get().name == "SortedSetBuilder" || c.get().name == "SortedSet"):
						": " + types.of(v.t, false);
					case _: "";
				};
				var initStr = switch(init.expr) {
					case TFunction(fn): functionValueLiteralNamed(v.name, fn, init.t);
					default: expr(init);
				};
				initStr = renderValueForType(v.t, init, initStr);
				// A String local owns its value; a literal initializer is
				// a &str, so the empty literal declares String::new() and
				// any other literal converts once at the declaration. A
				// Null<String> local additionally wraps in Some.
				if(isStringType(v.t)) {
					switch(stripWrap(init).expr) {
						case TConst(TString(s)):
							initStr = s.length == 0 ? "String::new()" : initStr + ".to_string()";
							if(isNullType(v.t)) {
								initStr = "Some(" + initStr + ")";
							}
						case _:
					}
				}
				if(!isTypeCopy(v.t)) {
					switch(stripWrap(init).expr) {
						case TArray(arr, _) if(!isLazyArrayReceiver(arr)):
							initStr = "&" + initStr;
						case _:
					}
				}
				return [indent(depth) + '$kw $name$explicitType = $initStr;'];
			case TVar(_, init) if(init == null):
				return [fail(e, "declaration without initializer has no lowering")];
			case TBlock(stmts):
				return blockLines(stmts, depth);
			case TIf(c, t, f):
				var condStr = expr(c);
				while(StringTools.startsWith(condStr, "(") && StringTools.endsWith(condStr, ")") && matchingParens(condStr)) {
					condStr = condStr.substr(1, condStr.length - 2);
				}
				final out = [indent(depth) + "if " + condStr + " {"];
				for(l in blockLines(statementsOf(t), depth + 1)) out.push(l);
				if(f != null) {
					out.push(indent(depth) + "} else {");
					for(l in blockLines(statementsOf(f), depth + 1)) out.push(l);
				}
				out.push(indent(depth) + "}");
				return out;
			case TWhile(c, b, true):
				var condStr = expr(c);
				while(StringTools.startsWith(condStr, "(") && StringTools.endsWith(condStr, ")") && matchingParens(condStr)) {
					condStr = condStr.substr(1, condStr.length - 2);
				}
				final out = [indent(depth) + "while " + condStr + " {"];
				for(l in blockLines(statementsOf(b), depth + 1)) out.push(l);
				out.push(indent(depth) + "}");
				return out;
			case TWhile(_, _, false):
				return [fail(e, "do-while has no lowering in the subset")];
			case TReturn(ret) if(ret == null):
				if(isFallible) {
					return [indent(depth) + "return Ok(());"];
				}
				return [indent(depth) + "return;"];
			case TReturn(ret) if(isTryRegion(ret)):
				return regionReturnLines(stripWrap(ret), depth);
			case TReturn(ret) if(isVariantSwitch(ret)):
				return matchReturnLines(stripWrap(ret), depth);
			case TReturn(ret):
				// An Int-returning function renders u32, while a length
				// expression renders usize; the return narrows once at the
				// boundary. Each length read keeps its native type; the conversion
				// occurs at the call boundary.
				var retStr = if(returnUnsigned && isUsizeExpr(ret)) {
					"(" + expr(ret) + ") as u32";
				} else {
					renderValueForType(currentReturnType, ret, expr(ret));
				};
				// A parameter-typed read clones at the boundary: the
				// element stays owned by its array.
				if(RustType.isTypeParam(ret.t)) {
					switch(stripWrap(ret).expr) {
						case TArray(_, _) | TField(_, _) | TLocal(_):
							retStr = "(" + retStr + ").clone()";
						case _:
					}
				}
				// String-bearing returns adjust once at the boundary: a
				// String function owns its value while a literal is a &str,
				// and an Option<String> return (Null<String>) wraps a plain
				// String expression in Some. Expressions that already carry
				// the Null type lower to Option themselves, and TNull
				// already renders None, so neither wraps again.
				if(returnTypeName == "String") {
					switch(stripWrap(ret).expr) {
						case TConst(TString(s)): retStr = s.length == 0 ? "String::new()" : retStr + ".to_string()";
						case _:
					}
				} else if(StringTools.startsWith(returnTypeName, "Option<") && !isNullType(ret.t) && !isTNull(ret)) {
					retStr = "Some(" + retStr + ")";
				} else if(StringTools.startsWith(returnTypeName, "Option<") && isIntType(ret.t) && !isNullType(ret.t) && !isTNull(ret)) {
					// An Int expression returned from a Null<Int> function
					// wraps once at the boundary; Null-typed expressions
					// already lower to Option and TNull renders None.
					retStr = "Some(" + retStr + ")";
				}
				if(isFallible) {
					return [indent(depth) + "return Ok(" + retStr + ");"];
				}
				return [indent(depth) + "return " + retStr + ";"];
			case TThrow(x):
				return [indent(depth) + "return Err(" + throwVariant(x) + ");"];
			case TTry(body, catches) if(catches.length == 1):
				return regionStatementLines(body, catches[0], depth);
			case TTry(_, _):
				return [fail(e, "try region handles exactly one exception domain")];
			case TBreak:
				return [indent(depth) + "break;"];
			case TContinue:
				return [indent(depth) + "continue;"];
			case TCall(fn, args) if(stringBufMutationParts(fn) != null):
				return stringBufMutationLines(fn, args, depth);
			case TMeta(_, inner):
				return stmtLines(inner, depth);
			case _:
				return [indent(depth) + expr(e) + ";"];
		}
	}

	function throwVariant(x: TypedExpr): String {
		final inner = stripWrap(x);
		switch(inner.expr) {
			case TNew(c, _, args) if(args.length == 1):
				return exceptionVariant(c.get(), args[0]);
			case _:
		}
		return expr(x);
	}

	/**
		The payload enum behind std.UStringException: every buffer check
		of stdlib/08 reports UnpairedSurrogate through it. Registers the
		import the hand-emitted Err arms need and returns the enum name,
		or null when the exception class is outside the module set.
	**/
	function stringBufFaultEnum(): Null<String> {
		final enumModule = state.exceptionPayloads.get("std.UStringException");
		if(enumModule == null) {
			return null;
		}
		final name = enumModule.split(".").pop();
		final emitted = state.payloadEnumModules.get(enumModule);
		final emittedIn = emitted != null ? emitted : "std.UStringException";
		imports.requireType(emittedIn, name);
		return name;
	}

	/**
		Recognizes `buf.add(part)` and `buf.addChar(unit)` on std.StringBuf;
		the pairing checks end the fallible owner through `return Err`, so
		these mutations lower as statements only.
	**/
	function stringBufMutationParts(fn: TypedExpr): Null<{name: String, subj: TypedExpr}> {
		return switch(fn.expr) {
			case TField(subj, FInstance(_, _, cf)) if(isStringBuf(subj)):
				final n = cf.get().name;
				n == "add" || n == "addChar" ? {name: n, subj: subj} : null;
			case _: null;
		};
	}

	/** Statement lowering of the two buffer mutations (stdlib/08). */
	function stringBufMutationLines(fn: TypedExpr, args: Array<TypedExpr>, depth: Int): Array<String> {
		final parts = stringBufMutationParts(fn);
		if(parts == null) {
			return [fail(fn, "not a string buffer mutation")];
		}
		if(!isFallible) {
			return [fail(fn, "string buffer " + parts.name + " has no lowering outside a fallible function: route the mutation through a fallible helper (stdlib/08)")];
		}
		final fault = stringBufFaultEnum();
		if(fault == null) {
			return [fail(fn, "string buffer checks require std.UStringException in the module set (stdlib/08)")];
		}
		final buf = expr(parts.subj);
		final out: Array<String> = [];
		if(parts.name == "add") {
			final part = expr(args[0]);
			out.push(indent(depth) + "if let Some(&unit) = " + buf + ".last() {");
			// A Rust &str is always well-formed, so no part can open with
			// the trail surrogate the contract would pair; the trail-start
			// clause of stdlib/08 folds away.
			out.push(indent(depth + 1) + "if unit >= 55296 && unit <= 56319 && !" + part + ".is_empty() {");
			out.push(indent(depth + 2) + "return Err(" + fault + "::UnpairedSurrogate { unit: unit as u32 });");
			out.push(indent(depth + 1) + "}");
			out.push(indent(depth) + "}");
			out.push(indent(depth) + buf + ".extend(" + part + ".encode_utf16());");
		} else {
			final u = expr(args[0]);
			out.push(indent(depth) + "if " + u + " >= 56320 && " + u + " <= 57343 {");
			out.push(indent(depth + 1) + "match " + buf + ".last() {");
			out.push(indent(depth + 2) + "Some(&last) if last >= 55296 && last <= 56319 => {}");
			out.push(indent(depth + 2) + "_ => return Err(" + fault + "::UnpairedSurrogate { unit: " + u + " }),");
			out.push(indent(depth + 1) + "}");
			out.push(indent(depth) + "} else if let Some(&last) = " + buf + ".last() {");
			out.push(indent(depth + 1) + "if last >= 55296 && last <= 56319 {");
			out.push(indent(depth + 2) + "return Err(" + fault + "::UnpairedSurrogate { unit: last as u32 });");
			out.push(indent(depth + 1) + "}");
			out.push(indent(depth) + "}");
			out.push(indent(depth) + buf + ".push(" + u + " as u16);");
		}
		return out;
	}

	function exceptionVariant(cls: ClassType, payloadArg: TypedExpr): String {
		// Name the payload enum from the thrown variant itself: each exception
		// class pairs with exactly one payload enum, and the enum is emitted
		// inside the exception class's module file.
		final arg = stripWrap(payloadArg);
		final payloadEnum = payloadEnumRef(arg);
		final errType = payloadEnum != null ? payloadEnum.get().name : (state.errorName != null ? state.errorName : "");
		final enumModule = payloadEnum != null ? payloadEnum.get().module : null;
		final emittedIn = enumModule != null && state.payloadEnumModules.exists(enumModule)
			? state.payloadEnumModules.get(enumModule)
			: cls.module;
		imports.requireType(emittedIn, errType);
		switch(arg.expr) {
			case TField(_, FEnum(_, ef)):
				return errType + "::" + ef.name;
			case TCall(fn, callArgs):
				switch(stripWrap(fn).expr) {
					case TField(_, FEnum(_, ef)):
						final efArgs = switch(ef.type) {
							case TFun(fargs, _): fargs;
							case _: [];
						};
						final parts = [];
						for(i in 0...callArgs.length) {
							final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
							parts.push(argName + ": " + expr(callArgs[i]));
						}
						return errType + "::" + ef.name + " { " + parts.join(", ") + " }";
					case _:
				}
			case _:
		}
		return errType + "::" + expr(payloadArg);
	}

	function payloadEnumRef(e: TypedExpr): Null<Ref<haxe.macro.Type.EnumType>> {
		return switch(e.expr) {
			case TField(_, FEnum(en, _)): en;
			case TCall(fn, _):
				switch(stripWrap(fn).expr) {
					case TField(_, FEnum(en, _)): en;
					case _: null;
				}
			case _: null;
		};
	}

	function fuseWithin(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TBlock(stmts):
				final fused = fuseUninitializedVars([for(s in stmts) fuseWithin(s)]);
				{expr: TBlock(fused), pos: e.pos, t: e.t};
			case _:
				TypedExprTools.map(e, fuseWithin);
		}
	}

	function fuseUninitializedVars(stmts: Array<TypedExpr>): Array<TypedExpr> {
		final out: Array<TypedExpr> = [];
		var i = 0;
		while(i < stmts.length) {
			switch(stmts[i].expr) {
				case TVar(v, init) if(init == null):
					var assignIdx = -1;
					var rhsExpr: Null<TypedExpr> = null;
					for(j in (i + 1)...stmts.length) {
						switch(stripCast(stmts[j]).expr) {
							case TBinop(OpAssign, lhs, rhs):
								switch(stripCast(lhs).expr) {
									case TLocal(assignedVar) if(assignedVar.id == v.id):
										assignIdx = j;
										rhsExpr = rhs;
									case _:
								}
							case _:
						}
						if(assignIdx != -1) break;
					}
					if(assignIdx != -1 && rhsExpr != null) {
						out.push({ expr: TVar(v, rhsExpr), pos: stmts[i].pos, t: stmts[i].t });
						stmts.splice(assignIdx, 1);
						i++;
						continue;
					}
				case _:
			}
			out.push(stmts[i]);
			i++;
		}
		return out;
	}

	/**
		`tailScope` marks the two scopes whose fallible bodies close with a
		synthesized result tail: the function body root and lambda bodies.
		Nested blocks never synthesize one regardless of depth; the old
		depth-equals-two test misfired whenever the root depth changed.
	**/
	function blockLines(stmts: Array<TypedExpr>, depth: Int, tailScope: Bool = false): Array<String> {
		stmts = fuseUninitializedVars(stmts);
		stmts = regroupLoops(stmts);
		stmts = transformCountdownLoops(stmts);
		final out: Array<String> = [];

		var i = 0;
		while(i < stmts.length) {
			final fused = fillFusion(stmts, i, depth);
			if(fused != null) {
				for(l in fused) out.push(l);
				i += 2;
				continue;
			}
			final loop = matchInterval(stmts[i]);
			if(loop != null) {
				for(l in loopLines(loop, depth)) out.push(l);
				i += 1;
				continue;
			}
			for(l in stmtLines(stmts[i], depth)) out.push(l);
			i += 1;
		}

		if(tailScope && isFallible) {
			var endsWithReturn = false;
			if(stmts.length > 0) {
				switch(stmts[stmts.length - 1].expr) {
					case TReturn(_) | TThrow(_): endsWithReturn = true;
					case _:
				}
			}
			if(!endsWithReturn) {
				out.push(indent(depth) + "Ok(())");
			}
		}

		return out;
	}

	function transformCountdownLoops(stmts: Array<TypedExpr>): Array<TypedExpr> {
		final out: Array<TypedExpr> = [];
		var i = 0;
		while(i < stmts.length) {
			if(i + 1 < stmts.length) {
				final cd = matchCountdownLoop(stmts[i], stmts[i + 1]);
				if(cd != null) {
					mutated.set(cd.readVar.id, true);
					final newDecl: TypedExpr = {
						expr: TVar(cd.readVar, cd.base),
						pos: stmts[i].pos,
						t: stmts[i].t
					};
					out.push(newDecl);

					final newCond = transformCountdownCond(cd.cond, cd.readVar.id);
					final newBodyStmts = statementsOf(cd.body).map(s -> shiftIndexExpr(s, cd.readVar.id));
					final newBody: TypedExpr = {
						expr: TBlock(newBodyStmts),
						pos: cd.body.pos,
						t: cd.body.t
					};
					final newWhile: TypedExpr = {
						expr: TWhile(newCond, newBody, true),
						pos: stmts[i + 1].pos,
						t: stmts[i + 1].t
					};
					out.push(newWhile);

					for(k in (i + 2)...stmts.length) {
						out.push(shiftIndexExpr(stmts[k], cd.readVar.id));
					}
					break;
				}
			}
			out.push(stmts[i]);
			i += 1;
		}
		return out;
	}

	function matchCountdownLoop(decl: TypedExpr, loop: TypedExpr): Null<{readVar: TVar, base: TypedExpr, cond: TypedExpr, body: TypedExpr}> {
		switch[decl.expr, loop.expr] {
			case [TVar(readVar, init), TWhile(cond, body, true)] if(init != null):
				final base = switch(stripWrap(init).expr) {
					case TBinop(OpSub, b, r):
						switch(stripWrap(r).expr) {
							case TConst(TInt(1)): b;
							case _: null;
						};
					case _: null;
				};
				if(base == null) {
					return null;
				}
				if(!hasGteZeroCheck(cond, readVar.id)) {
					return null;
				}
				if(!mentionsDecrement(statementsOf(body), readVar.id)) {
					return null;
				}
				return {readVar: readVar, base: base, cond: cond, body: body};
			case _:
				return null;
		}
	}

	function hasGteZeroCheck(cond: TypedExpr, varId: Int): Bool {
		final inner = stripWrap(cond);
		switch(inner.expr) {
			case TBinop(OpBoolAnd, l, _):
				return isGteZero(l, varId);
			case _:
				return isGteZero(inner, varId);
		}
	}

	function isGteZero(e: TypedExpr, varId: Int): Bool {
		final inner = stripWrap(e);
		return switch(inner.expr) {
			case TBinop(OpGte, l, r):
				switch[stripWrap(l).expr, stripWrap(r).expr] {
					case [TLocal(v), TConst(TInt(0))] if(v.id == varId): true;
					case _: false;
				};
			case TBinop(OpLte, l, r):
				switch[stripWrap(l).expr, stripWrap(r).expr] {
					case [TConst(TInt(0)), TLocal(v)] if(v.id == varId): true;
					case _: false;
				};
			case TBinop(OpGt, l, r):
				switch[stripWrap(l).expr, stripWrap(r).expr] {
					case [TLocal(v), TConst(TInt(-1))] if(v.id == varId): true;
					case _: false;
				};
			case _: false;
		}
	}

	function transformCountdownCond(cond: TypedExpr, varId: Int): TypedExpr {
		final inner = stripWrap(cond);
		switch(inner.expr) {
			case TBinop(OpBoolAnd, l, r) if(isGteZero(l, varId)):
				final v = findLocalVar(l, varId);
				final newL: TypedExpr = {
					expr: TBinop(OpGt, {expr: TLocal(v), pos: l.pos, t: l.t}, {expr: TConst(TInt(0)), pos: l.pos, t: l.t}),
					pos: l.pos,
					t: l.t
				};
				final newR = shiftIndexExpr(r, varId);
				return {
					expr: TBinop(OpBoolAnd, newL, newR),
					pos: cond.pos,
					t: cond.t
				};
			case _:
				if(isGteZero(inner, varId)) {
					final v = findLocalVar(inner, varId);
					return {
						expr: TBinop(OpGt, {expr: TLocal(v), pos: inner.pos, t: inner.t}, {expr: TConst(TInt(0)), pos: inner.pos, t: inner.t}),
						pos: cond.pos,
						t: cond.t
					};
				}
				return shiftIndexExpr(cond, varId);
		}
	}

	function findLocalVar(e: TypedExpr, varId: Int): TVar {
		var found: Null<TVar> = null;
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TLocal(v) if(v.id == varId): found = v;
				case _:
			}
			TypedExprTools.iter(x, walk);
		}
		walk(e);
		return found;
	}

	function mentionsDecrement(stmts: Array<TypedExpr>, varId: Int): Bool {
		var found = false;
		for(s in stmts) {
			function walk(x: TypedExpr) {
				switch(x.expr) {
					case TBinop(OpAssignOp(OpSub), l, _) if(isTargetVar(l, varId)):
						found = true;
					case TBinop(OpAssign, l, r) if(isTargetVar(l, varId)):
						switch(stripWrap(r).expr) {
							case TBinop(OpSub, subTarget, _) if(isTargetVar(subTarget, varId)):
								found = true;
							case _:
						}
					case TUnop(OpDecrement, _, subj) if(isTargetVar(subj, varId)):
						found = true;
					case _:
				}
				TypedExprTools.iter(x, walk);
			}
			walk(s);
		}
		return found;
	}

	function isTargetVar(e: TypedExpr, varId: Int): Bool {
		return switch(stripWrap(e).expr) {
			case TLocal(v) if(v.id == varId): true;
			case _: false;
		};
	}

	function shiftIndexExpr(e: TypedExpr, varId: Int): TypedExpr {
		switch(e.expr) {
			case TBinop(OpAdd, l, r):
				switch[stripWrap(l).expr, stripWrap(r).expr] {
					case [TLocal(v), TConst(TInt(1))] if(v.id == varId):
						return l;
					case [TConst(TInt(1)), TLocal(v)] if(v.id == varId):
						return r;
					case _:
				}
			case TBinop(OpAssignOp(op), l, r) if(isTargetVar(l, varId)):
				return {
					expr: TBinop(OpAssignOp(op), l, shiftIndexExpr(r, varId)),
					pos: e.pos,
					t: e.t
				};
			case TBinop(OpAssign, l, r) if(isTargetVar(l, varId)):
				return {
					expr: TBinop(OpAssign, l, shiftAssignRhs(r, varId)),
					pos: e.pos,
					t: e.t
				};
			case TUnop(OpDecrement, post, subj) if(isTargetVar(subj, varId)):
				return e;
			case TLocal(v) if(v.id == varId):
				return {
					expr: TBinop(OpSub, e, {expr: TConst(TInt(1)), pos: e.pos, t: e.t}),
					pos: e.pos,
					t: e.t
				};
			case _:
		}
		return TypedExprTools.map(e, x -> shiftIndexExpr(x, varId));
	}

	function shiftAssignRhs(r: TypedExpr, varId: Int): TypedExpr {
		final inner = stripWrap(r);
		switch(inner.expr) {
			case TBinop(OpSub, l, rightSub) if(isTargetVar(l, varId)):
				return {
					expr: TBinop(OpSub, l, shiftIndexExpr(rightSub, varId)),
					pos: r.pos,
					t: r.t
				};
			case _:
				return shiftIndexExpr(r, varId);
		}
	}

	// ------------------------------------------------------------------
	// Counted loops
	// ------------------------------------------------------------------

	function regroupLoops(stmts: Array<TypedExpr>): Array<TypedExpr> {
		final out: Array<TypedExpr> = [];
		var i = 0;
		while(i < stmts.length) {
			if(i + 2 < stmts.length) {
				final loop = intervalCore(stmts[i], stmts[i + 1], stmts[i + 2]);
				if(loop != null) {
					final grouped: TypedExpr = {
						expr: TBlock([stmts[i], stmts[i + 1], stmts[i + 2]]),
						pos: stmts[i].pos,
						t: stmts[i + 2].t
					};
					out.push(grouped);
					i += 3;
					continue;
				}
			}
			out.push(stmts[i]);
			i += 1;
		}
		return out;
	}

	function intervalCore(counterDecl: TypedExpr, boundDecl: TypedExpr, whileExpr: TypedExpr): Null<{index: TVar, start: TypedExpr, bound: TypedExpr, body: Array<TypedExpr>}> {
		switch[counterDecl.expr, boundDecl.expr, whileExpr.expr] {
			case [TVar(counter, start), TVar(boundVar, bound), TWhile(cond, body, true)]:
				final condOk = switch(stripWrap(cond).expr) {
					case TBinop(OpLt, l, r):
						final lc = stripWrap(l);
						final rc = stripWrap(r);
						switch[lc.expr, rc.expr] {
							case [TLocal(c), TLocal(b)]: c.id == counter.id && b.id == boundVar.id;
							case _: false;
						}
					case _: false;
				}
				if(!condOk) {
					return null;
				}
				final bodyStmts = statementsOf(body);
				if(bodyStmts.length == 0) {
					return null;
				}
				switch(bodyStmts[0].expr) {
					case TVar(captured, inc):
						final captureOk = inc != null && switch(stripWrap(inc).expr) {
							case TUnop(OpIncrement, true, subj):
								switch(stripWrap(subj).expr) {
									case TLocal(c): c.id == counter.id;
									case _: false;
								}
							case _: false;
						}
						if(!captureOk) {
							return null;
						}
						return {index: captured, start: start, bound: bound, body: bodyStmts.slice(1)};
					case _:
						return null;
				}
			case _:
				return null;
		}
	}

	function matchInterval(e: TypedExpr): Null<{index: TVar, start: TypedExpr, bound: TypedExpr, body: Array<TypedExpr>}> {
		switch(e.expr) {
			case TBlock(stmts) if(stmts.length == 3):
				return intervalCore(stmts[0], stmts[1], stmts[2]);
			case TBlock(stmts) if(stmts.length == 2):
				return intervalShort(stmts[0], stmts[1]);
			case _:
				return null;
		}
	}

	function intervalShort(counterDecl: TypedExpr, whileExpr: TypedExpr): Null<{index: TVar, start: TypedExpr, bound: TypedExpr, body: Array<TypedExpr>}> {
		switch[counterDecl.expr, whileExpr.expr] {
			case [TVar(counter, start), TWhile(cond, body, true)]:
				final bound = switch(stripWrap(cond).expr) {
					case TBinop(OpLt, {expr: TLocal(c)}, right) if(c.id == counter.id): right;
					case _: return null;
				};
			final bodyStmts = statementsOf(body);
			if(bodyStmts.length == 0) return null;
			switch(bodyStmts[0].expr) {
				case TVar(captured, inc) if(inc != null):
					switch(stripWrap(inc).expr) {
						case TUnop(OpIncrement, true, {expr: TLocal(c)}) if(c.id == counter.id):
							return {index: captured, start: start, bound: bound, body: bodyStmts.slice(1)};
						case _:
					}
				case _:
			}
			case _:
		}
		return null;
	}

	function loopLines(loop, depth: Int): Array<String> {
		rangeLoopVars.set(loop.index.id, true);
		final name = RustImports.toSnakeCase(loop.index.name);
		final sliceSubj = sliceIterationSubject(loop);
		if(sliceSubj != null) {
			final itemVar = sliceItemVar(loop.body, loop.index, sliceSubj);
			if(itemVar != null) {
				final itemName = RustImports.toSnakeCase(itemVar.name);
				final isScalar = switch(Context.follow(itemVar.t)) {
					case TAbstract(a, _):
						final n = a.get().name;
						n == "Int" || n == "Bool" || n == "Float";
					default: false;
				};
				final argType = switch(stripWrap(sliceSubj).expr) {
					case TLocal(v): argTypes.get(v.name);
					default: null;
					};
				// A scalar loop over an owned local array borrows the array: the
				// pattern takes a reference and the array stays usable after the
				// loop. Parameters already arrive as rendered references.
				final ownedLocal = isScalar && argType == null;
				final pattern = if(isScalar) {
					if(argType != null) {
						StringTools.startsWith(argType, "&mut") ? "&mut " + itemName : "&" + itemName;
					} else {
						"&" + itemName;
					}
				} else {
					itemName;
				};
				final iterated = ownedLocal ? "&" + expr(sliceSubj) : expr(sliceSubj);
				switch(Context.follow(itemVar.t)) {
					case TAbstract(a, _) if(a.get().name == "Int"):
						// Array elements reach Rust as u32; remember the loop binding
						// so negative-domain checks lower as upper-bound checks.
						unsignedLocals.set(itemVar.id, true);
					case _:
				}
				final remainingBody = loop.body.slice(1);
				final gb = matchGroupByBody(remainingBody);
				if(gb != null) {
					final entryName = RustImports.toSnakeCase(gb.entryVar.name);
					final entryExprStr = expr(gb.entryInit);
					final builderStr = expr(gb.builderSubj);
				final kGetExpr = sortedRefArg(gb.keyArg);
				final kPutExpr = sortedRefArg(gb.keyArg);
					final valStr = renderPushArg(gb.valArg);
					final out = [
						indent(depth) + "for " + pattern + " in " + iterated + " {"
					];
					for(l in blockLines(gb.prefix, depth + 1)) out.push(l);
					out.push(indent(depth + 1) + "let " + entryName + " = " + entryExprStr + ";");
					out.push(indent(depth + 1) + "let mut pipeline_bucket = match " + builderStr + ".get(" + kGetExpr + ") {");
					out.push(indent(depth + 2) + "Some(b) => b,");
					out.push(indent(depth + 2) + "None => Vec::new(),");
					out.push(indent(depth + 1) + "};");
					out.push(indent(depth + 1) + "pipeline_bucket.push(" + valStr + ");");
					out.push(indent(depth + 1) + builderStr + ".put(" + kPutExpr + ", &pipeline_bucket);");
					out.push(indent(depth) + "}");
					return out;
				}

				final out = [
					indent(depth) + "for " + pattern + " in " + iterated + " {"
				];
				for(l in blockLines(remainingBody, depth + 1)) out.push(l);
				out.push(indent(depth) + "}");
				return out;
			}
		}

		final startStr = expr(loop.start);
		final boundStr = loopBound(loop.bound);
		final out = [
			indent(depth) + "for " + name + " in " + startStr + ".." + boundStr + " {"
		];
		for(l in blockLines(loop.body, depth + 1)) out.push(l);
		out.push(indent(depth) + "}");
		return out;
	}

	function sliceIterationSubject(loop: {index: TVar, start: TypedExpr, bound: TypedExpr, body: Array<TypedExpr>}): Null<TypedExpr> {
		final innerStart = stripWrap(loop.start);
		final isStartZero = switch(innerStart.expr) {
			case TConst(TInt(0)): true;
			case _: false;
		};
		if(!isStartZero) return null;
		final innerBound = stripWrap(loop.bound);
		return switch(innerBound.expr) {
			case TField(subj, fa) if(fieldName(fa) == "length"):
				if(EnumQueryExpander.collectionEnum(subj) != null) return null;
				switch(stripWrap(subj).expr) {
					case TLocal(_): subj;
					case _: null;
				}
			case _: null;
		};
	}

	function sliceItemVar(body: Array<TypedExpr>, indexVar: TVar, sliceSubj: TypedExpr): Null<TVar> {
		if(body.length == 0) return null;
		return switch(body[0].expr) {
			case TVar(itemVar, init) if(init != null):
				switch(stripWrap(init).expr) {
					case TArray(subj, idx):
						final subjOk = switch[stripWrap(subj).expr, stripWrap(sliceSubj).expr] {
							case [TLocal(s1), TLocal(s2)]: s1.id == s2.id;
							case _: false;
						};
						final idxOk = switch(stripWrap(idx).expr) {
							case TLocal(iv): iv.id == indexVar.id;
							case _: false;
						};
						if(subjOk && idxOk) itemVar else null;
					case _: null;
				}
			case _: null;
		};
	}

	function loopBound(bound: TypedExpr): String {
		final inner = stripWrap(bound);
		switch(inner.expr) {
			case TField(subj, fa) if(fieldName(fa) == "length"):
				final enumCollection = EnumQueryExpander.collectionEnum(subj);
				if(enumCollection != null) return Std.string(EnumQueryExpander.constructorCount(enumCollection));
				return expr(subj) + ".len()";
			case _:
				return expr(bound);
		}
	}

	// ------------------------------------------------------------------
	// Counted fill (Vec::with_capacity)
	// ------------------------------------------------------------------

	function fillFusion(stmts: Array<TypedExpr>, i: Int, depth: Int): Null<Array<String>> {
		if(i + 1 >= stmts.length) {
			return null;
		}
		final alloc: Null<{arr: TVar, elem: Type}> = switch(stmts[i].expr) {
			case TVar(v, init) if(init != null):
				switch(init.expr) {
					case TNew(c, params, args) if(args.length == 0):
						final cls = c.get();
						if(cls.pack.join(".") != "" || cls.name != "Array" || params.length != 1) {
							null;
						} else {
							{arr: v, elem: params[0]};
						}
					case _: null;
				}
			case _: null;
		}
		if(alloc == null) {
			return null;
		}
		final loop = matchInterval(stmts[i + 1]);
		if(loop == null) {
			return null;
		}

		var storeValue: Null<TypedExpr> = null;
		var pushArg: Null<TypedExpr> = null;
		var ok = true;
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null) {
				if(store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
					if(storeValue != null) {
						ok = false;
					}
					storeValue = store.value;
				} else {
					ok = false;
				}
				continue;
			}
			final push = pushOf(s);
			if(push != null) {
				if(push.arr.id == alloc.arr.id) {
					if(pushArg != null || storeValue != null) {
						ok = false;
					}
					pushArg = push.arg;
				} else {
					ok = false;
				}
				continue;
			}
			if(mentionsLocal(s, alloc.arr)) {
				ok = false;
			}
		}
		if(!ok || (storeValue == null && pushArg == null)) {
			return null;
		}

		final arrName = RustImports.toSnakeCase(localName(alloc.arr));
		final capStr = capacityExpr(loop.bound);
		final boundStr = loopBound(loop.bound);
		final loopIndexName = RustImports.toSnakeCase(loop.index.name);

		// Check if loop index is mentioned in body outside the array store index
		var loopVarMentioned = false;
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				if(mentionsLocal(store.value, loop.index)) {
					loopVarMentioned = true;
				}
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				if(mentionsLocal(push.arg, loop.index)) {
					loopVarMentioned = true;
				}
				continue;
			}
			if(mentionsLocal(s, loop.index)) {
				loopVarMentioned = true;
			}
		}

		final loopVar = loopVarMentioned ? loopIndexName : "_";

		final out: Array<String> = [];
		out.push(indent(depth) + "let capacity = " + capStr + ";");
		out.push(indent(depth) + "let mut " + arrName + " = Vec::with_capacity(capacity);");
		out.push(indent(depth) + "for " + loopVar + " in 0.." + boundStr + " {");
		final nonStores: Array<TypedExpr> = [];
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + ".push(" + renderPushArg(store.value) + ");");
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + ".push(" + renderPushArg(push.arg) + ");");
				continue;
			}
			nonStores.push(s);
		}
		if(nonStores.length > 0) {
			for(l in blockLines(nonStores, depth + 1)) out.push(l);
		}
		out.push(indent(depth) + "}");
		return out;
	}

	function sortedKeyType(fn: TypedExpr): Null<haxe.macro.Type.Type> {
		return switch(fn.t) {
			case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
			case _: null;
		};
	}

	function sortedValueType(fn: TypedExpr): Null<haxe.macro.Type.Type> {
		return switch(fn.t) {
			case TFun(_, TInst(_, params)) if(params.length > 1): params[1];
			case _: null;
		};
	}

	/**
		Comparator a builder site binds: the resident integer walk
		adapted to the unsigned business domain, the resident string
		walk, or the per-structure generated comparator.
	**/
	function sortedComparator(kType: Null<haxe.macro.Type.Type>, pos: haxe.macro.Expr.Position): String {
		if(kType == null) {
			Context.error("sorted builder requires an explicit key type", pos);
		}
		return switch(RustType.classifyKey(kType, pos)) {
			case IntKey: "Box::new(|a, b| SortedTable::compare_ints((*a) as i32, (*b) as i32))";
			case StringKey: "Box::new(|a, b| SortedTable::compare_strings(a.as_str(), b.as_str()))";
			case StructKey(def, _):
				final cmpName = "compare_" + RustImports.toSnakeCase(def.name);
				imports.requireType(def.module, cmpName);
				"Box::new(" + cmpName + ")";
		};
	}

	/**
		Every table parameter borrows: keys and values arrive as
		references and the resident clones what it stores. String keys
		construct when the expression is a literal or a borrowed &str.
	**/
	function sortedRefArg(arg: TypedExpr): String {
		if(isStringType(arg.t)) {
			switch(stripWrap(arg).expr) {
				case TConst(TString(_)):
					return "&(" + expr(arg) + ").to_string()";
				case TLocal(v):
					final pt = types.of(v.t, true);
					return pt == "&str" ? "&(" + expr(arg) + ").to_string()" : "&" + expr(arg);
				case _:
					return "&" + expr(arg);
			}
		}
		return "&(" + expr(arg) + ")";
	}

	function isBorrowedLocal(v: haxe.macro.Type.TVar): Bool {
		final stored = argTypes.get(v.name);
		return stored != null && StringTools.startsWith(stored, "&");
	}

	function renderPushArg(arg: TypedExpr): String {
		var argStr = expr(arg);
		if(isNullType(arg.t)) {
			argStr = argStr + ".unwrap()";
			if(!isTypeCopy(getNullInnerType(arg.t))) {
				if(!StringTools.endsWith(argStr, ".clone()") && !StringTools.endsWith(argStr, ".to_vec()") && !StringTools.endsWith(argStr, ".to_string()")) {
					argStr = argStr + ".clone()";
				}
			}
			return argStr;
		}
		if(!isTypeCopy(arg.t)) {
			switch(stripWrap(arg).expr) {
				// The base constant renderer emits a bare &str literal, so
				// pushing one into a String array needs an owned conversion.
				case TConst(TString(_)):
					argStr = argStr + ".to_string()";
				case TNew(_, _, _):
				case TLocal(v) if(isBorrowedLocal(v)):
					// The local holds a reference (a borrowed parameter):
					// clone the referent so the array owns its element.
					argStr = "(*" + argStr + ").clone()";
				case TLocal(_) | TField(_) | TArray(_, _):
					if(!StringTools.endsWith(argStr, ".clone()") && !StringTools.endsWith(argStr, ".to_vec()") && !StringTools.endsWith(argStr, ".to_string()")) {
						argStr = argStr + ".clone()";
					}
				default:
			}
		}
		return argStr;
	}

	function capacityExpr(bound: TypedExpr): String {
		// Constant and length bounds cannot overflow; every other bound needs
		// the overflow variant of the resolved error enum.
		final inner = stripWrap(bound);
		switch(inner.expr) {
			case TConst(TInt(n)) if(n >= 0):
				return Std.string(n);
			case TField(subj, fa) if(fieldName(fa) == "length"):
				return expr(subj) + ".len()";
			case _:
				if(errorTypeName == null || countOverflowVariant == null) {
					Context.error("cannot lower fallible capacity expression: missing error enum or overflow variant", bound.pos);
					return "0";
				}
				final errVariant = errorTypeName + "::" + countOverflowVariant;
				return "usize::try_from(" + expr(bound) + ").map_err(|_| " + errVariant + ")?";
		}
	}

	function indexedStoreOf(s: TypedExpr): Null<{arr: TVar, idx: TVar, value: TypedExpr}> {
		switch(stripWrap(s).expr) {
			case TBinop(OpAssign, target, value):
				switch(stripWrap(target).expr) {
					case TArray(arr, idx):
						final arrLocal = stripWrap(arr);
						final idxLocal = stripWrap(idx);
						switch[arrLocal.expr, idxLocal.expr] {
							case [TLocal(a), TLocal(ix)]: return {arr: a, idx: ix, value: value};
							case _:
						}
					case _:
				}
			case _:
		}
		return null;
	}

	function pushOf(s: TypedExpr): Null<{arr: TVar, arg: TypedExpr}> {
		switch(stripWrap(s).expr) {
			case TCall(fn, args) if(args.length == 1):
				switch(stripWrap(fn).expr) {
					case TField(subj, fa) if(fieldName(fa) == "push"):
						switch(stripWrap(subj).expr) {
							case TLocal(a): return {arr: a, arg: args[0]};
							case _:
						}
					case _:
				}
			case _:
		}
		return null;
	}

	// ------------------------------------------------------------------
	// Expressions
	// ------------------------------------------------------------------

	function expr(e: TypedExpr): String {
		final int64Expr = int64Expression(e);
		if(int64Expr != null) return int64Expr;
		final wrapperValue = ValueTypeSupport.syntheticValue(e);
		if(wrapperValue != null) return valueTypeSynthetic(e, wrapperValue);
		final query = enumQuery(e);
		if(query != null) return query;
		switch(e.expr) {
			case TConst(c):
				switch(c) {
					case TInt(v):
						// Haxe Int is 32-bit two's-complement; the business
						// module real is u32, so a negative literal carries
						// the same bits as its wrapped unsigned decimal with
						// an explicit u32 suffix: the suffix keeps boundary
						// casts to i32 bit-preserving. Resident modules keep
						// the signed i32 rendering.
						if(v < 0 && !RuntimeResidents.isResident(imports.selfModule)) {
							return Std.string(v + 4294967296) + "u32";
						}
						return Std.string(v);
					case TFloat(f):
						final s = Std.string(f);
						final padded = s.indexOf(".") >= 0 ? s : s + ".0";
						// The f32 configuration marks every literal so its width never
						// depends on the inference context (feature spec 23).
						return FloatPrecision.isF32() ? padded + "f32" : padded;
					case TString(s): return quoteString(s);
					case TBool(b): return b ? "true" : "false";
					case TNull: return "None";
					case TThis: return "self";
					case TSuper: return "super";
					case _: return fail(e, "constant has no Rust lowering");
				}
			case TLocal(v):
				if(subst.exists(v.id)) {
					return subst.get(v.id);
				}
				return RustImports.toSnakeCase(localName(v));
			case TArray(arr, idx):
				final mapReceiver = mapBackingReceiver(arr);
				if(mapReceiver != null) {
					return expr(mapReceiver) + ".get(&" + rustMapKey(idx) + ").cloned()";
				}
				final staticGuard = staticGuardOf(arr);
				if(staticGuard != null) {
					final base = staticGuard + "[" + staticIndex(idx) + "]";
					return scalarTypeKind(e.t) == "String" ? "(" + base + ").clone()" : base;
				}
				final receiver = expr(arr);
				final receiverText = StringTools.startsWith(receiver, "&*") ? "(" + receiver + ")" : receiver;
				final base = receiverText + "[(" + expr(idx) + ") as usize]";
				// Reading a String element moves it out of the Vec, so a
				// value read renders as a clone. Borrow consumers go
				// through arrayArgBorrow and skip the copy.
				return isLazyArrayReceiver(arr) && !isTypeCopy(e.t) || scalarTypeKind(e.t) == "String" ? "(" + base + ").clone()" : base;
			case TBinop(op, l, r):
				return binop(e, op, l, r);
			case TUnop(op, post, subj):
				return unop(e, op, post, subj);
			case TField(subj, fa):
				return field(subj, fa);
			case TTypeExpr(t):
				return typeExpr(t);
			case TParenthesis(inner):
				return "(" + expr(inner) + ")";
			case TObjectDecl(fields):
				return objectLiteral(e, fields);
			case TArrayDecl(elems):
				final isStringElem = switch(Context.follow(e.t)) {
					case TInst(c, params) if(c.get().name == "Array" && params.length > 0 && isStringType(params[0])): true;
					case _: false;
				};
				final rendered = [for(x in elems) {
					if(isStringElem) {
						switch(stripWrap(x).expr) {
							case TConst(TString(_)): expr(x) + ".to_string()";
							case TLocal(v) if(paramVarIds.exists(v.id)): expr(x) + ".to_string()";
							case _: expr(x) + ".clone()";
						}
					} else {
						expr(x);
					}
				}];
				return "vec![" + rendered.join(", ") + "]";
			case TCall(fn, args):
				return call(fn, args);
			case TNew(c, params, args):
				return newExpr(c, params, args);
			case TMeta(_, inner):
				return expr(inner);
			case TCast(inner, _):
				return expr(inner);
			case TEnumParameter(se, ef, index):
				// A collapsed single-case switch reads the payload outside
				// any match arm; a one-construct enum folds the read into an
				// exhaustive match, and anything wider stays in arms.
				final en = switch(Context.follow(se.t)) {
					case TEnum(r, _): r.get();
					case _: return fail(e, "payload read subject is not a variant value");
				};
				if(Lambda.count(en.constructs) != 1) {
					return fail(e, "payload read of a multi-variant enum lowers inside a match arm only");
				}
				requireEnum(en.module, en.name);
				final pname = payloadName(ef, index);
				return "match " + expr(se) + " { " + en.name + "::" + ef.name + " { " + pname + ", .. } => " + pname + " }";
			case TEnumIndex(_):
				return fail(e, "enum index only lowers inside a variant switch");
			case TFunction(f):
				return functionValueLiteral(f, e.t);
			case TIf(c, t, f) if(f != null):
				final coalescing = coalescingSiteFor(e);
				if(coalescing != null) return expr(coalescing.valueExpr);
				final optional = optionalIf(c, t, f, e.t);
				if(optional != null) return optional;
				final condStr = switch(stripWrap(c).expr) {
					case _: expr(stripWrap(c));
				};
				return "if " + condStr + " { " + conditionalBranchText(t, f) + " } else { " + conditionalBranchText(f, t) + " }";
			case TSwitch(_, _, _):
				return matchExpression(e);
			case TTry(_, catches) if(catches.length != 1):
				return fail(e, "try region handles exactly one exception domain");
			case TTry(_, _):
				// Region lowering needs the statement context (features/06):
				// statement position and initializer position render in
				// stmtLines, return position in TReturn.
				return fail(e, "try region lowers at statement, initializer, or return position");
			case _:
				return fail(e, "expression has no Rust lowering in the subset: " + Std.string(e.expr));
			}
	}

	function optionalIf(c: TypedExpr, ifTrue: TypedExpr, ifFalse: TypedExpr, resultType: Type): Null<String> {
		var value: Null<TVar> = null;
		var trueIsNone = false;
		switch(stripWrap(c).expr) {
			case TBinop(OpEq, left, right):
				if(isTNull(right)) {
					switch(stripWrap(left).expr) {
						case TLocal(v): value = v; trueIsNone = true;
						case _:
					}
				} else if(isTNull(left)) {
					switch(stripWrap(right).expr) {
						case TLocal(v): value = v; trueIsNone = true;
						case _:
					}
				}
			case TBinop(OpNotEq, left, right):
				if(isTNull(right)) {
					switch(stripWrap(left).expr) {
						case TLocal(v): value = v; trueIsNone = false;
						case _:
					}
				} else if(isTNull(left)) {
					switch(stripWrap(right).expr) {
						case TLocal(v): value = v; trueIsNone = false;
						case _:
					}
				}
			case _:
		}
		if(value == null) {
			return null;
		}
		final selected = trueIsNone ? ifFalse : ifTrue;
		switch(stripWrap(selected).expr) {
			case TLocal(v) if(v.id == value.id):
				final noneExpr = trueIsNone ? ifTrue : ifFalse;
				final noneText = expr(noneExpr);
				final typedNoneText = isStringType(resultType) ? noneText + ".to_string()" : noneText;
				final localName = RustImports.toSnakeCase(value.name);
				return "match " + localName + " { None => " + typedNoneText + ", Some(" + localName + ") => " + localName + " }";
			case _:
		}
		return null;
	}

	/** Lowers an abstract implementation block to a Rust newtype value. */
	function valueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr):String {
		final abs = ValueTypeSupport.markedAbstractOfType(wrapper.t);
		if(abs == null) return expr(value);
		imports.requireType(abs.module, abs.name);
		final wrapperName = abs.name;
		final locals = valueTypeLocalValues(wrapper);
		final activeAbs = currentClass == null ? null : ValueTypeSupport.markedAbstractOfClass(currentClass);
		final activeField = activeAbs != null && currentMethodName != null ? ValueTypeSupport.memberField(activeAbs, currentMethodName) : null;
		final nativeOperator = activeAbs != null && activeField != null && ValueTypeSupport.sameAbstract(activeAbs, abs)
			&& ValueTypeSupport.operatorOf(abs, activeField) != null;
		return switch(stripWrap(value).expr) {
			case TBinop(op, left, right):
				final field = ValueTypeSupport.binaryOperatorField(abs, op);
				if(field == null) expr(value) else {
					final asRepresentation = nativeOperator && field.name == currentMethodName;
					final rendered = valueTypeOperand(left, locals, abs, asRepresentation) + " " + opStr(op) + " " + valueTypeOperand(right, locals, abs, asRepresentation);
					nativeOperator && field.name == currentMethodName ? wrapperName + "(" + rendered + ")" : rendered;
				}
			case TUnop(op, _, subject):
				final field = ValueTypeSupport.unaryOperatorField(abs, op);
				if(field == null) expr(value) else {
					final asRepresentation = nativeOperator && field.name == currentMethodName;
					final rendered = "-" + valueTypeOperand(subject, locals, abs, asRepresentation);
					nativeOperator && field.name == currentMethodName ? wrapperName + "(" + rendered + ")" : rendered;
				}
			case _: wrapperName + "(" + expr(value) + ")";
		};
	}

	function valueTypeLocalValues(wrapper:TypedExpr):Map<Int, TypedExpr> {
		final values:Map<Int, TypedExpr> = [];
		switch(wrapper.expr) {
			case TBlock(stmts):
				for(stmt in stmts) switch(stmt.expr) {
					case TVar(v, init) if(init != null && !StringTools.startsWith(v.name, "this")): values.set(v.id, init);
					case _:
				}
			case _:
		}
		return values;
	}

	function valueTypeOperand(value:TypedExpr, locals:Map<Int, TypedExpr>, ?abs:AbstractType, asRepresentation:Bool = false):String {
		var source = value;
		var wrapperOperand = false;
		var decorated = true;
		while(decorated) {
			if(abs != null) {
				final sourceAbs = ValueTypeSupport.markedAbstractOfType(source.t);
				if(sourceAbs != null && ValueTypeSupport.sameAbstract(sourceAbs, abs)) wrapperOperand = true;
			}
			switch(source.expr) {
				case TCast(inner, _): source = inner;
				case TMeta(_, inner): source = inner;
				case _: decorated = false;
			}
		}
		switch(stripWrap(value).expr) {
			case TLocal(v) if(locals.exists(v.id)): return expr(locals.get(v.id));
			case _:
		}
		final rendered = expr(value);
		final alreadyRepresentation = switch(stripWrap(value).expr) {
			case TLocal(v) if(subst.exists(v.id) && StringTools.endsWith(subst.get(v.id), ".0")): true;
			case _: false;
		};
		return asRepresentation && wrapperOperand && !alreadyRepresentation ? rendered + ".0" : rendered;
	}

	function enumQuery(e:TypedExpr):Null<String> {
		switch(e.expr) {
			case TField(subj, fa): final name = switch(fa) { case FInstance(_, _, cf) | FAnon(cf): cf.get().name; case FDynamic(n): n; case _: ""; }; final en = EnumQueryExpander.collectionEnum(subj); if(name == "length" && en != null) return Std.string(EnumQueryExpander.constructorCount(en));
			case TArray(subj, index): final en = EnumQueryExpander.collectionEnum(subj); if(en != null) { if(EnumQueryExpander.aliasEnum(subj) != null) return expr(subj) + "[" + expr(index) + "]"; requireEnum(en.module, en.name); return en.name + "::ALL[" + expr(index) + "]"; }
			case _:
		}
		final kind = EnumQueryExpander.markerKind(e); if(kind == null) return null; final en = EnumQueryExpander.enumOf(e); final args = EnumQueryExpander.callArgs(e); requireEnum(en.module, en.name);
		return switch(kind) { case QCollection: en.name + "::ALL"; case QName: expr(args[0]) + ".name()"; case QLookup: en.name + "::from_name(&(" + expr(args[1]) + "))"; };
	}

	// ------------------------------------------------------------------
	// Variant switches and try regions (features/01, features/06)
	// ------------------------------------------------------------------

	function isTryRegion(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TTry(_, catches): catches.length == 1;
			case _: false;
		};
	}

	/** True when the expression is an enum switch over variant indices. */
	function isVariantSwitch(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TSwitch(_, _, _): true;
			case _: false;
		};
	}

	/** Return-position variant switch: the match value returns through the function edge. */
	function matchReturnLines(sw: TypedExpr, depth: Int): Array<String> {
		final lines = matchExpression(sw).split("\n");
		final out = [indent(depth) + (isFallible ? "return Ok(" : "return ") + lines[0]];
		for(i in 1...lines.length) {
			out.push(indent(depth) + lines[i]);
		}
		out[out.length - 1] += isFallible ? ");" : ";";
		return out;
	}

	/**
		On a catch variable, the payload field of the exception class (the
		enum-typed field whose enum the region catches) reads as the bound
		enum value itself; the exception class is unavailable for this target
		(features/06 catch-site lowering).
	**/
	function catchPayloadAccess(subj: TypedExpr, name: String): Null<String> {
		switch(stripWrap(subj).expr) {
			case TLocal(v) if(catchVars.exists(v.id)):
				switch(Context.follow(v.t)) {
					case TInst(c, _):
						final cls = c.get();
						final enumModule = state.exceptionPayloads.get(cls.module);
						if(enumModule != null) {
							for(f in cls.fields.get()) {
								if(f.name == name) {
									switch(f.type) {
										case TEnum(en, _):
											if(en.get().module == enumModule) {
												return RustImports.toSnakeCase(localName(v));
											}
										case _:
									}
								}
							}
						}
					case _:
				}
			case _:
		}
		return null;
	}

	/** The payload enum of the exception class a region catches, or null. */
	function caughtPayloadEnum(c: {v: TVar, expr: TypedExpr}): Null<{name: String, module: String}> {
		switch(Context.follow(c.v.t)) {
			case TInst(cls, _):
				final enumModule = state.exceptionPayloads.get(cls.get().module);
				if(enumModule == null) {
					return null;
				}
				final name = enumModule.substr(enumModule.lastIndexOf(".") + 1);
				return {name: name, module: enumModule};
			case _:
				return null;
		}
	}

	function requireEnum(enumModule: String, enumName: String): Void {
		final emittedIn = state.payloadEnumModules.exists(enumModule) ? state.payloadEnumModules.get(enumModule) : enumModule;
		imports.requireType(emittedIn, enumName);
	}

	function freshRegionName(prefix: String): String {
		var index = 0;
		var name = prefix;
		while(usedNames.exists(name)) {
			index += 1;
			name = prefix + index;
		}
		usedNames.set(name, true);
		return name;
	}

	/**
		Renders the region body as an immediately invoked closure returning
		`Result<value, enum>`. The trailing value expression is rewrapped as a
		return so the existing fallible return edge rules (String ownership,
		Option wrapping) apply at the `Ok` tail; the fallibility flag is set
		for the closure body only, so `Ok` wrapping holds even when the
		enclosing function absorbed the domain.
	**/
	function regionClosureLines(body: TypedExpr, regionType: Null<Type>, enumName: String, depth: Int): Array<String> {
		var stmts = statementsOf(body);
		// A top-level throw ends the region: the tail after it is dead in
		// every target, so the closure stops at the throwing edge.
		for(i in 0...stmts.length) {
			switch(stmts[i].expr) {
				case TThrow(_):
					stmts = stmts.slice(0, i + 1);
					break;
				case _:
			}
		}
		final tail = regionTailValue(stmts);
		var bodyStmts = stmts;
		if(tail != null) {
			final rewrapped: TypedExpr = {expr: TypedExprDef.TReturn(tail), t: tail.t, pos: tail.pos};
			bodyStmts = stmts.slice(0, stmts.length - 1).concat([rewrapped]);
		}
		final savedFallible = isFallible;
		final savedError = errorTypeName;
		final savedOverflow = countOverflowVariant;
		isFallible = true;
		errorTypeName = enumName;
		countOverflowVariant = null;
		final lines = blockLines(bodyStmts, depth, true);
		isFallible = savedFallible;
		errorTypeName = savedError;
		countOverflowVariant = savedOverflow;
		// A Void tail still closes with Ok(()): blockLines appends it under
		// the forced fallible flag, and a rewrapped tail already returns it.
		return lines;
	}

	/**
		The trailing value of a region body: an expression statement whose
		value leaves the region. Declarations, control flow, assignments,
		and blocks never carry the tail value.
	**/
	function regionTailValue(stmts: Array<TypedExpr>): Null<TypedExpr> {
		if(stmts.length == 0) {
			return null;
		}
		final last = stmts[stmts.length - 1];
		return switch(last.expr) {
			case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TFor(_, _, _) | TBlock(_) | TBreak | TContinue | TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
				null;
			case _:
				isVoidType(last.t) ? null : last;
		}
	}

	function isVoidType(t: Null<Type>): Bool {
		if(t == null) {
			return true;
		}
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Void";
			case TEnum(en, _): en.get().name == "Void";
			case _: false;
		};
	}

	/** Return-position region: the match value returns through the function edge. */
	function regionReturnLines(region: TypedExpr, depth: Int): Array<String> {
		final parts = switch(stripWrap(region).expr) {
			case TTry(body, catches): {body: body, c: catches[0]};
			case _: return [fail(region, "not a try region")];
		}
		final payload = caughtPayloadEnum(parts.c);
		if(payload == null) {
			return [fail(parts.c.expr, "try region catch type carries no payload enum")];
		}
		if(regionTailValue(statementsOf(parts.body)) == null) {
			return [fail(region, "try region body has no value")];
		}
		requireEnum(payload.module, payload.name);
		final valueBinding = freshRegionName("__value");
		// The annotated return type keeps the error enum readable at the
		// closure head; handler arms alone cannot always infer it.
		final valueType = types.of(regionTailValue(statementsOf(parts.body)).t);
		final opener = "(|| -> Result<" + valueType + ", " + payload.name + "> {";
		final prefix = isFallible ? "return Ok(match " + opener : "return match " + opener;
		final out = [indent(depth) + prefix];
		for(l in regionClosureLines(parts.body, region.t, payload.name, depth + 1)) out.push(l);
		out.push(indent(depth) + (isFallible ? "})() {" : "})() {"));
		out.push(indent(depth) + "    Ok(" + valueBinding + ") => " + valueBinding + ",");
		catchVars.set(parts.c.v.id, true);
		final arm = armBlock(parts.c.expr);
		catchVars.remove(parts.c.v.id);
		for(i in 0...arm.length) {
			final suffix = i == arm.length - 1 ? "," : "";
			out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(parts.c.v)) + ") => " + arm[i] + suffix);
		}
		out.push(indent(depth) + (isFallible ? "});" : "};"));
		return out;
	}

	/** Statement-position region: run the closure, act on the Err arm only. */
	function regionStatementLines(body: TypedExpr, c: {v: TVar, expr: TypedExpr}, depth: Int): Array<String> {
		final payload = caughtPayloadEnum(c);
		if(payload == null) {
			return [fail(c.expr, "try region catch type carries no payload enum")];
		}
		requireEnum(payload.module, payload.name);
		final outcome = freshRegionName("__outcome");
		final tail = regionTailValue(statementsOf(body));
		final valueType = tail != null ? tail.t : null;
		final out = [indent(depth) + 'let $outcome: Result<' + (valueType == null ? "()" : types.of(valueType)) + ', ' + payload.name + "> = (|| {"];
		for(l in regionClosureLines(body, valueType, payload.name, depth + 1)) out.push(l);
		out.push(indent(depth) + "})();");
		out.push(indent(depth) + 'match $outcome {');
		out.push(indent(depth) + "    Ok(_) => {}");
		out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(c.v)) + ") => {");
		catchVars.set(c.v.id, true);
		final handler = blockLines(statementsOf(c.expr), depth + 2);
		catchVars.remove(c.v.id);
		for(l in handler) out.push(l);
		out.push(indent(depth) + "    }");
		out.push(indent(depth) + "}");
		return out;
	}

	/** Initializer-position region: the match yields the bound value. */
	function regionInitializerLines(v: TVar, region: TypedExpr, depth: Int): Array<String> {
		final parts = switch(stripWrap(region).expr) {
			case TTry(body, catches): {body: body, c: catches[0]};
			case _: return [fail(region, "not a try region")];
		}
		final payload = caughtPayloadEnum(parts.c);
		if(payload == null) {
			return [fail(parts.c.expr, "try region catch type carries no payload enum")];
		}
		if(regionTailValue(statementsOf(parts.body)) == null) {
			return [fail(region, "try region body has no value")];
		}
		requireEnum(payload.module, payload.name);
		final name = RustImports.toSnakeCase(localName(v));
		final valueBinding = freshRegionName("__value");
		final out = [indent(depth) + 'let $name: ' + types.of(v.t) + ' = match (|| -> Result<' + types.of(v.t) + ', ' + payload.name + '> {'];
		for(l in regionClosureLines(parts.body, v.t, payload.name, depth + 1)) out.push(l);
		out.push(indent(depth) + "})() {");
		out.push(indent(depth) + "    Ok(" + valueBinding + ") => " + valueBinding + ",");
		catchVars.set(parts.c.v.id, true);
		final arm = armBlock(parts.c.expr);
		catchVars.remove(parts.c.v.id);
		for(i in 0...arm.length) {
			final suffix = i == arm.length - 1 ? "," : "";
			out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(parts.c.v)) + ") => " + arm[i] + suffix);
		}
		out.push(indent(depth) + "};");
		return out;
	}

	/**
		Renders an enum switch as a `match` expression. The typer hands the
		switch over with the subject wrapped in TEnumIndex and case values as
		construct-index constants; payload captures arrive as TEnumParameter
		initializations in the arm block, so each arm pattern binds the
		captured payloads as named fields and represents the remaining fields with `..`.
	**/
	function matchExpression(sw: TypedExpr): String {
		final parts = switch(sw.expr) {
			case TSwitch(subj, cases, def): {subj: subj, cases: cases, def: def};
			case _: return fail(sw, "not a switch");
		}
		if(parts.def != null) {
			return fail(sw, "variant switch carries a default arm (V15)");
		}
		final subj = stripWrap(parts.subj);
		final se = switch(subj.expr) {
			case TEnumIndex(inner): inner;
			case _: return fail(sw, "switch subject is not a variant index");
		}
		final subjStr = expr(se);
		final en = switch(se.t) {
			case TEnum(enumRef, _): enumRef.get();
			case _: return fail(sw, "variant switch subject is not a variant value");
		}
		requireEnum(en.module, en.name);
		final table = new Map<Int, EnumField>();
		for(constructName => ef in en.constructs) {
			table.set(ef.index, ef);
		}
		final out = ["match " + subjStr + " {"];
		for(c in parts.cases) {
			final index = switch(c.values[0].expr) {
				case TConst(TInt(v)): v;
				case _: return fail(sw, "variant switch case is not a constant index");
			}
			final ef = table.get(index);
			if(ef == null) {
				return fail(sw, "variant switch case index has no construct");
			}
			final argCount = switch(ef.type) {
				case TFun(args, _): args.length;
				case _: 0;
			};
			// Payload captures bind as named fields of the variant pattern;
			// uncaptured payloads use `..`; unused ones use a
			// leading underscore binding.
			final subjectLocal = switch(se.expr) {
				case TLocal(l): l.id;
				case _: -1;
			};
			final captures: Array<{vid: Int, idx: Int}> = [];
			function collect(stmts: Array<TypedExpr>) {
				for(s in stmts) {
					switch(s.expr) {
						case TVar(v, init) if(init != null):
							switch(stripWrap(init).expr) {
								case TEnumParameter(se2, _, idx):
									switch(se2.expr) {
										case TLocal(l2) if(l2.id == subjectLocal):
											if(Lambda.find(captures, function(c) return c.idx == idx) == null) {
												captures.push({vid: v.id, idx: idx});
											}
										case _:
									}
								// The typer binds the pattern variable from
								// the extraction temp; usage tracking follows
								// the pattern variable, so a payload the arm
								// value never reads stays out of the pattern.
								case TLocal(src):
									for(cap in captures) {
										if(cap.vid == src.id) {
											cap.vid = v.id;
										}
									}
								case _:
							}
						case TBlock(bs):
							collect(bs);
						case _:
					}
				}
			}
			collect(statementsOf(c.expr));
			function localIsRead(vid: Int): Bool {
				// TypedExprTools.iter visits direct children only, so the
				// read scan must recurse through the callback (mentionsLocal
				// pattern); payload reads sit under TVar initializers.
				var found = false;
				function scan(x: TypedExpr) {
					switch(x.expr) {
						case TLocal(l) if(l.id == vid):
							found = true;
						case _:
					}
					TypedExprTools.iter(x, scan);
				}
				scan(c.expr);
				return found;
			}
			final usedIndices = [for(cap in captures) if(localIsRead(cap.vid)) cap.idx];
			var lastUsed = -1;
			for(idx in usedIndices) {
				if(idx > lastUsed) {
					lastUsed = idx;
				}
			}
			var pattern = en.name + "::" + ef.name;
			if(argCount > 0) {
				final bindings: Array<String> = [];
				for(idx in 0...argCount) {
					if(Lambda.has(usedIndices, idx)) {
						bindings.push(payloadName(ef, idx));
					} else if(idx < lastUsed) {
						// An unused payload before a used one still binds,
						// under the underscore name.
						bindings.push("_" + payloadName(ef, idx));
					} else {
						// Everything from the first unused tail payload on
						// represents the remaining fields with the rest pattern.
						bindings.push("..");
						break;
					}
				}
				pattern += " { " + bindings.join(", ") + " }";
			}
			final arm = armBlock(c.expr);
			for(i in 0...arm.length) {
				final suffix = i == arm.length - 1 ? "," : "";
				out.push("    " + pattern + " => " + arm[i] + suffix);
			}
		}
		out.push("}");
		return out.join("\n");
	}

	/**
		Renders one switch arm (or one region handler in value position).
		Payload captures fold into field reads on the subject; other
		declarations stay; the trailing statement is the arm value. A
		single-expression arm renders inline, anything longer renders as a
		block.
	**/
	function armBlock(e: TypedExpr): Array<String> {
		final decls: Array<String> = [];
		var value: Null<String> = null;
		var sawReturn = false;
		function walk(stmts: Array<TypedExpr>) {
			for(s in stmts) {
				switch(s.expr) {
					case TVar(v, init):
						if(init == null) {
							Context.error("rust target: declaration without initializer has no lowering", s.pos);
						}
						switch(stripWrap(init).expr) {
							case TEnumParameter(_, ef, index):
								// The variant pattern binds the payload as a
								// named field, so the capture reads it bare.
								subst.set(v.id, payloadName(ef, index));
							case TLocal(source) if(subst.exists(source.id)):
								subst.set(v.id, subst.get(source.id));
							case _:
								decls.push("let " + RustImports.toSnakeCase(localName(v)) + " = " + expr(init) + ";");
						}
					case TBlock(bs):
						walk(bs);
					case TMeta(_, inner):
						walk([inner]);
					case TReturn(_):
						sawReturn = true;
					case _:
						value = expr(s);
				}
			}
		}
		walk(statementsOf(e));
		if(sawReturn) {
			return [fail(e, "return inside a value arm lowers at statement position only")];
		}
		if(value == null) {
			return [fail(e, "variant switch arm has no value")];
		}
		if(decls.length == 0) {
			return [value];
		}
		final out = ["{"];
		for(d in decls) {
			out.push("    " + d);
		}
		out.push("    " + value);
		out.push("}");
		return out;
	}

	function isStringType(t: Type): Bool {		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TInst(c, _): c.get().name == "String";
			case _: false;
		};
	}

	function isSortedBuilder(subj: TypedExpr): Bool {
		return switch(Context.follow(subj.t)) {
			case TInst(c, _):
				final n = c.get().name;
				n == "SortedMapBuilder" || n == "SortedSetBuilder";
			case _: false;
		};
	}

	function isSortedTable(subj: TypedExpr): Bool {
		return switch(Context.follow(subj.t)) {
			case TInst(c, _):
				final n = c.get().name;
				n == "SortedMap" || n == "SortedSet";
			case _: false;
		};
	}

	function isTypeCopy(t: Type): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TAbstract(a, _):
				final n = a.get().name;
				n == "Int" || n == "Bool" || n == "Float";
			case TAnonymous(anon):
				isAllCopy(anon.get().fields);
			case TType(d, _):
				switch(d.get().type) {
					case TAnonymous(anon):
						isAllCopy(anon.get().fields);
					case _: false;
				}
			case TLazy(fn):
				isTypeCopy(fn());
			case TEnum(en, _):
				var copy = true;
				for(ef in en.get().constructs) switch(Context.follow(ef.type)) {
					case TFun(args, _) if(args.length > 0): copy = false;
					case _:
				}
				copy;
			case _: false;
		};
	}

	function isAllCopy(fields: Array<ClassField>): Bool {
		for(f in fields) {
			if(!isTypeCopy(f.type)) return false;
		}
		return true;
	}

	function binop(e: TypedExpr, op: Binop, l: TypedExpr, r: TypedExpr): String {
		final fromBe = tryMatchFromBeBytes(e);
		if(fromBe != null) {
			return fromBe;
		}
			switch(op) {
			case OpEq | OpNotEq if(nullableEnumComparedWithEnum(l.t, r.t) || nullableEnumComparedWithEnum(r.t, l.t)):
				final left = isNullType(l.t) ? expr(l) : "Some(" + expr(l) + ")";
				final right = isNullType(r.t) ? expr(r) : "Some(" + expr(r) + ")";
				return left + " " + symbolOf(op) + " " + right;
			// A nullable operand compared against the null literal lowers
			// to a predicate call: Option equality against None would
			// require PartialEq on the inner type, which the emitted
			// structs do not carry.
			case OpEq | OpNotEq if((isNullType(l.t) && isTNull(r)) || (isNullType(r.t) && isTNull(l))):
				final nullable = isNullType(l.t) ? l : r;
				return expr(nullable) + (op == OpEq ? ".is_none()" : ".is_some()");
			case OpAssign:
				final map = mapAssignment(l);
				if(map != null) {
					return expr(map.receiver) + ".insert(" + rustMapKey(map.key) + ", " + rustMapValue(r) + ")";
				}
				final staticTarget = staticAssignmentTarget(l);
				if(staticTarget != null) {
					final staticValue = if(StaticFieldHelper.isNullableType(l.t)) {
						isTNull(r) ? "None" : "Some(" + staticOwnedValue(r) + ")";
					} else if(StaticFieldHelper.isStringType(l.t)) {
						staticOwnedValue(r);
					} else {
						expr(r);
					};
					return staticTarget + " = " + staticValue;
				}
				final rhs = if(isNullType(l.t) && !isNullType(r.t) && !isTNull(r)) {
					final rStr = if(!isTypeCopy(r.t)) {
						switch(stripWrap(r).expr) {
							// A literal is a &str while the Null target owns
							// Option<String>; clone does not exist on str.
							case TConst(TString(_)): expr(r) + ".to_string()";
							case _:
								final s = expr(r);
								if(!StringTools.endsWith(s, ".clone()") && !StringTools.endsWith(s, ".to_vec()") && !StringTools.endsWith(s, ".to_string()")) {
									s + ".clone()";
								} else {
									s;
								}
						}
					} else {
						expr(r);
					};
					"Some(" + rStr + ")";
				} else if(isStringType(l.t) && !isNullType(l.t)) {
					switch(stripWrap(r).expr) {
						case TConst(TString(_)): expr(r) + ".to_string()";
						default: expr(r);
					}
				} else {
					numericAssignmentValue(l.t, r, renderValueForType(l.t, r, expr(r)));
				};
				return assignTarget(l) + " = " + rhs;
			case OpAssignOp(inner):
				// String accumulation borrows the operand: String
				// implements AddAssign<&str>, and the += desugaring makes
				// the right side a coercion site, so &(expr) accepts both
				// String expressions and literals.
				switch(inner) {
					case OpAdd if(isStringType(l.t) && !isNullType(l.t) && isStringType(r.t) && !isNullType(r.t)):
						return assignTarget(l) + " += &(" + expr(r) + ")";
					case _:
				}
				return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
			case OpAdd if(isStringType(l.t) || isStringType(r.t)):
				final leftStd = stdStringArg(l);
				final rightStd = stdStringArg(r);
				final lStr = leftStd != null ? stdString(leftStd, true) : (isNullType(l.t) ? expr(l) + ".as_deref().unwrap_or(\"\")" : expr(l));
				final rStr = rightStd != null ? stdString(rightStd, true) : (isNullType(r.t) ? expr(r) + ".as_deref().unwrap_or(\"\")" : expr(r));
				return "format!(\"{}{}\", " + lStr + ", " + rStr + ")";
			case OpDiv if(StringTools.endsWith(operand(l, op, false), ".len()")):
				return "((" + operand(l, op, false) + ") / (" + operand(r, op, true) + " as usize)) as i32";
			case OpMult | OpAdd | OpSub | OpDiv if(isFloatType(e.t)):
				final real = FloatPrecision.isF32() ? "f32" : "f64";
				final lStr = if(isIntType(l.t)) "((" + operand(l, op, false) + ") as " + real + ")" else operand(l, op, false);
				final rStr = if(isIntType(r.t)) "((" + operand(r, op, true) + ") as " + real + ")" else operand(r, op, true);
				return lStr + " " + symbolOf(op) + " " + rStr;
			case OpAnd:
				final rightInner = stripWrap(r);
				final isMask255 = switch(rightInner.expr) {
					case TConst(TInt(255)): true;
					case _: false;
				};
				if(isMask255) {
					final byteExt = tryMatchByteExtract(l);
					if(byteExt != null) {
						return byteExt;
					}
				}
				return operand(l, op, false) + " & " + operand(r, op, true);
			case OpUShr:
				// The u32 domain makes Rust >> the logical shift; operand()
				// re-adds grouping parens by precedence, so a bare shift
				// initializer carries no outer parentheses.
				return operand(l, op, false) + " >> " + operand(r, op, true);
			case OpLt if(isZero(r) && isUnsignedOperand(l)):
				return expr(l) + " > 2147483647";
			case OpSub:
				return operand(l, op, false) + " - " + operand(r, op, true);
			case _:
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
		}
	}

	function nullableEnumComparedWithEnum(nullable:Type, value:Type):Bool {
		if(!isNullType(nullable)) return false;
		return switch(Context.follow(getNullInnerType(nullable))) {
			case TEnum(_, _): switch(Context.follow(value)) { case TEnum(_, _): true; case _: false; };
			case _: false;
		};
	}

	function isZero(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(TInt(0)): true;
			case _: false;
		};
	}

	/**
		Haxe Int reaches Rust as u32 for values and usize for byte positions, so
		a negative-domain check can only be expressed as an upper-bound check on
		those operands; signed operands keep the literal comparison.
	**/
	function isUnsignedOperand(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TLocal(v): unsignedLocals.exists(v.id) || isUnsignedTypeName(argTypes.get(v.name));
			case _: false;
		};
	}

	function isUnsignedTypeName(n: Null<String>): Bool {
		return n == "u16" || n == "u32" || n == "usize";
	}

	function operand(e: TypedExpr, parent: Binop, isRight: Bool): String {
		final rendered = expr(e);
		switch(e.expr) {
			case TBinop(op, _, _):
				final cp = precedenceOf(op);
				final pp = precedenceOf(parent);
				var parens = cp < pp || (cp == pp && isRight && !associative(op));
				return parens ? "(" + rendered + ")" : rendered;
			case _:
				return rendered;
		}
	}

	function unop(e: TypedExpr, op: Unop, post: Bool, subj: TypedExpr): String {
		final inner = expr(subj);
		switch(op) {
			case OpNot: return "!" + inner;
			case OpNegBits: return "!" + inner;
			case OpNeg: return "-" + inner;
			case OpIncrement: return inner + " += 1";
			case OpDecrement: return inner + " -= 1";
			case _:
				return fail(e, "unary operator has no lowering: " + Std.string(op));
		}
	}

	function int64Expression(e:TypedExpr):Null<String> {
		return switch(e.expr) {
			case TCall(fn, args): int64Call(fn, args);
			case _: null;
		};
	}

	function int64Call(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
		return switch(stripWrap(fn).expr) {
			case TField(_, FStatic(classRef, fieldRef)) if(classRef.get().module == "haxe.Int64" && classRef.get().name == "Int64_Impl_"):
				switch(fieldRef.get().name) {
					case "make" if(args.length == 2): "(((" + expr(args[0]) + " as i64) << 32) | ((" + expr(args[1]) + " as u32) as i64))";
					case "ofInt" if(args.length == 1): "(" + expr(args[0]) + " as i32) as i64";
					case "getHigh" | "get_high" if(args.length == 1):
						if(isFpHelperInt64Halves(args[0])) expr(args[0]) + ".high" else "(" + expr(args[0]) + " >> 32) as u32";
					case "getLow" | "get_low" if(args.length == 1):
						if(isFpHelperInt64Halves(args[0])) expr(args[0]) + ".low" else expr(args[0]) + " as u32";
					case "add" if(args.length == 2): expr(args[0]) + ".wrapping_add(" + expr(args[1]) + ")";
					case "sub" if(args.length == 2): expr(args[0]) + ".wrapping_sub(" + expr(args[1]) + ")";
					case "and" if(args.length == 2): expr(args[0]) + " & " + expr(args[1]);
					case "or" if(args.length == 2): expr(args[0]) + " | " + expr(args[1]);
					case "xor" if(args.length == 2): expr(args[0]) + " ^ " + expr(args[1]);
					case "complement" if(args.length == 1): "!" + expr(args[0]);
					case "shl" if(args.length == 2): expr(args[0]) + ".wrapping_shl(" + expr(args[1]) + " as u32)";
					case "shr" if(args.length == 2): expr(args[0]) + ".wrapping_shr(" + expr(args[1]) + " as u32)";
					case "ushr" if(args.length == 2): "((" + expr(args[0]) + " as u64).wrapping_shr(" + expr(args[1]) + " as u32)) as i64";
					case "eq" if(args.length == 2): expr(args[0]) + " == " + expr(args[1]);
					case "neq" if(args.length == 2): expr(args[0]) + " != " + expr(args[1]);
					default: null;
				}
			default: null;
		};
	}

	function isFpHelperInt64Halves(e:TypedExpr):Bool {
		return switch(stripWrap(e).expr) {
			case TCall(fn, _): isFpHelperInt64Call(fn);
			case TLocal(v): fpInt64Halves.exists(v.id);
			case _: false;
		};
	}

	function isFpHelperInt64Call(fn:TypedExpr):Bool {
		return switch(stripWrap(fn).expr) {
			case TField(_, FStatic(classRef, fieldRef)):
				classRef.get().module == "haxe.io.FPHelper" && (fieldRef.get().name == "doubleToI64" || fieldRef.get().name == "f32ToI64");
			case _: false;
		};
	}

	function field(subj: TypedExpr, fa: FieldAccess): String {
		switch(fa) {
			case FStatic(c, cf):
				final cls = c.get();
				final name = cf.get().name;
				if(isLazyStaticField(cls, name) && !StaticFieldHelper.isSelfConstruction(cf.get(), cls)) {
					return "&*" + staticItemPath(cls, name);
				}
				if(isGuardStaticField(cls, name)) {
					if(StaticFieldHelper.isConstruction(cf.get().expr()) && !StaticFieldHelper.isSelfConstruction(cf.get(), cls)) {
						return "&*" + staticItemPath(cls, name);
					}
					final guard = staticGuard(cls, name);
					return StaticFieldHelper.isArrayType(cf.get().type) ? guard : guard + ".clone()";
				}
				final rendered = staticRef(cls, name);
				return StaticFieldHelper.isStringType(cf.get().type) ? rendered + ".to_string()" : rendered;
			case FEnum(e, ef):
				final en = e.get();
				imports.requireType(en.module, en.name);
				return en.name + "::" + ef.name;
			case FInstance(_, _, cf) | FAnon(cf):
				final name = cf.get().name;
				{
					final bound = catchPayloadAccess(subj, name);
					if(bound != null) {
						return bound;
					}
				}
				if(name == "message" || name == "get_message") {
					switch(stripWrap(subj).expr) {
						case TLocal(v) if(catchVars.exists(v.id)):
							// Display carries the message text of the variant
							// (features/06: messages are display text).
							return "format!(\"{}\", " + RustImports.toSnakeCase(localName(v)) + ")";
						case _:
					}
				}
				final staticGuard = staticGuardOf(subj);
				if(staticGuard != null) {
					if(name == "length") {
						return rustU32Length(staticGuard + ".len()");
					}
					return staticGuard + "." + RustImports.toSnakeCase(name);
				}
				if(name == "length") {
					if(isNullType(subj.t)) {
						return "(" + expr(subj) + ").as_ref().map_or(0, |v| v.len())";
					}
					if(isStringBuf(subj)) {
						return expr(subj) + ".len() as u32";
					}
					// Resident modules keep the signed Int domain: their
					// lengths join index arithmetic, so the read narrows
					// here the way UStringPlatform end inlines.
					if(RuntimeResidents.isResident(imports.selfModule)) {
						return "(" + expr(subj) + ").len() as i32";
					}
					final receiver = expr(subj);
					final receiverText = StringTools.startsWith(receiver, "&*") ? "(" + receiver + ")" : receiver;
					return receiverText + ".len()";
				}
				final snake = RustImports.toSnakeCase(name);
				final subjStr = if(isNullType(subj.t)) expr(subj) + ".as_ref().unwrap()" else expr(subj);
				final access = subjStr + "." + snake;
				if(name != "length" && isConstructedStaticRead(subj) && StaticFieldHelper.isStringType(cf.get().type)) return "(" + access + ").to_string()";
				return name != "length" && isConstructedStaticRead(subj) && !isTypeCopy(cf.get().type) ? "(" + access + ").clone()" : access;
			case FDynamic(name):
				if((name == "length" || name == "get_length") && isStringBuf(subj)) {
					return expr(subj) + ".len() as u32";
				}
				return fail(subj, "dynamic field access has no lowering");
			case FClosure(_):
				return fail(subj, "closure has no lowering");
		}
	}

	function staticFieldOf(cls: ClassType, name: String): Null<ClassField> {
		for(field in cls.statics.get()) {
			if(field.name == name) {
				return field;
			}
		}
		return null;
	}

	function isLazyStaticField(cls: ClassType, name: String): Bool {
		final field = staticFieldOf(cls, name);
		return field != null && (StaticFieldHelper.isConstruction(field.expr()) || isLazyArrayStaticField(field));
	}

	function isLazyArrayStaticField(field: ClassField): Bool {
		final init = StaticFieldHelper.initializer(field);
		return field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init) && !StaticFieldHelper.isIntLiteralArray(init);
	}

	function isDirectArrayStaticField(field: ClassField): Bool {
		final init = StaticFieldHelper.initializer(field);
		return field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init) && StaticFieldHelper.isIntLiteralArray(init);
	}

	function isLazyArrayReceiver(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TField(_, FStatic(c, cf)): isLazyArrayStaticField(cf.get());
			case _: false;
		};
	}

	function isGuardStaticField(cls: ClassType, name: String): Bool {
		final field = staticFieldOf(cls, name);
		return field != null
			&& ValueTypeSupport.markedAbstractOfClass(cls) == null
			&& StaticFieldHelper.initializer(field) != null
			&& !StaticFieldHelper.isConstValue(field)
			&& !DataTableHelper.isDataTableField(field)
			&& !isDirectArrayStaticField(field)
			&& !isLazyArrayStaticField(field)
			&& (!StaticFieldHelper.isConstruction(field.expr()) || StaticFieldHelper.isSelfConstruction(field, cls));
	}

	function staticItemPath(cls: ClassType, name: String): String {
		final itemName = RustImports.toSnakeCase(name);
		return cls.module == imports.selfModule
			? itemName
			: "crate::" + RustImports.moduleToRustPath(cls.module) + "::" + itemName;
	}

	function staticGuard(cls: ClassType, name: String): String {
		return staticItemPath(cls, name) + ".lock().unwrap_or_else(|e| e.into_inner())";
	}

	function staticGuardOf(e: TypedExpr): Null<String> {
		return switch(stripWrap(e).expr) {
			case TField(_, FStatic(c, cf)) if(isGuardStaticField(c.get(), cf.get().name)):
				staticGuard(c.get(), cf.get().name);
			case _: null;
		};
	}

	function staticIndex(e: TypedExpr): String {
		return switch(stripWrap(e).expr) {
			case TConst(TInt(value)): Std.string(value) + "usize";
			case _:
				"match usize::try_from(" + expr(e) + ") { Ok(value) => value, Err(_) => 0usize }";
		};
	}

	function rustU32Length(length: String): String {
		return "match u32::try_from(" + length + ") { Ok(value) => value, Err(_) => u32::MAX }";
	}

	function staticAssignmentTarget(e: TypedExpr): Null<String> {
		return switch(stripWrap(e).expr) {
			case TField(_, FStatic(c, cf)) if(isGuardStaticField(c.get(), cf.get().name)):
				"*" + staticGuard(c.get(), cf.get().name);
			case _: null;
		};
	}

	function isConstructedStaticRead(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TField(_, FStatic(c, cf)) if(StaticFieldHelper.isConstruction(cf.get().expr()) && !StaticFieldHelper.isSelfConstruction(cf.get(), c.get())): true;
			case _: false;
		};
	}

	function staticOwnedValue(e: TypedExpr): String {		final rendered = expr(e);
		if(StaticFieldHelper.isConstruction(e)) return rendered;
		if(StaticFieldHelper.isStringType(e.t)) {
			if(rendered.indexOf("&*") >= 0) return rendered + ".to_string()";
			return StringTools.endsWith(rendered, ".to_string()") || StringTools.endsWith(rendered, ".clone()")
				? rendered
				: rendered + ".to_string()";
		}
		if(!isTypeCopy(e.t) && !StringTools.endsWith(rendered, ".clone()") && !StringTools.endsWith(rendered, ".to_vec()")) {
			return rendered + ".clone()";
		}
		return rendered;
	}

	function staticContainerArg(e: TypedExpr): String {
		final rendered = expr(e);
		if(StaticFieldHelper.isConstruction(e)) return rendered;
		if(StaticFieldHelper.isStringType(e.t)
			&& !StringTools.endsWith(rendered, ".clone()")) {
			return rendered + ".to_string()";
		}
		return rendered;
	}

	function isFunctionType(t: Null<Type>): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TFun(_, _): true;
			case _: false;
		};
	}

	function staticFunctionName(name: String): String {
		return RustImports.toSnakeCase(name).toUpperCase();
	}

	function staticRef(cls: ClassType, name: String): String {
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) {
			imports.requireType(valueType.module, valueType.name);
			return valueType.name + "::" + RustImports.toSnakeCase(name);
		}
		final markedField = findStaticField(cls, name);
		if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
			final nativeName = RustImports.toSnakeCase(name);
			if(markedField.isPublic) {
				imports.requireType(cls.module, nativeName);
			}
			return nativeName;
		}
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "String":
				return "String::" + RustImports.toSnakeCase(name);
			case "Math":
				// The f32 configuration renders the whole Math family from f32, the
				// binary32 equivalent of every static (feature spec 23).
				final real = FloatPrecision.isF32() ? "f32" : "f64";
				if(name == "NaN") return real + "::NAN";
				if(name == "POSITIVE_INFINITY") return real + "::INFINITY";
				if(name == "NEGATIVE_INFINITY") return real + "::NEG_INFINITY";
				return real + "::" + RustImports.toSnakeCase(name);
			case "std.Test" | "std.__test_shim":
				state.shimsUsed.set("std.Test", true);
				if(name == "run") {
					imports.require("crate::runtime::test as testlib");
					return "testlib::run";
				}
				imports.require("crate::runtime::test_core");
				return "test_core::TestCore::" + RustImports.toSnakeCase(name);
			case "std.UStringRT":
				return uStringRef(name);
			case "std.Graphemes":
				// The extern fronts the resident runtime module
				// runtime.Graphemes, compiled into graphemes.rs; the
				// reference names the struct and calls its methods.
				state.shimsUsed.set("std.Graphemes", true);
				if(name == "boundaries" && !RuntimeResidents.isResident(imports.selfModule)) {
					// The boundary vector crosses whole between the two
					// Int domains; the adapter in graphemes.rs casts each
					// element once, because Array results have no
					// call-site cast machinery (RuntimeResidents).
					imports.require("crate::runtime::graphemes");
					return "graphemes::boundaries";
				}
				imports.requireType("runtime.Graphemes", "Graphemes");
				return "Graphemes::" + RustImports.toSnakeCase(name);
			case _:
				if(cls.module == "std.Test") {
					state.shimsUsed.set("std.Test", true);
					if(name == "run") {
						imports.require("crate::runtime::test as testlib");
						return "testlib::run";
					}
					imports.require("crate::runtime::test_core");
					return "test_core::TestCore::" + RustImports.toSnakeCase(name);
				}
				if(cls.module == "std.UStringRT") {
					return uStringRef(name);
				}
				if(cls.module == "std.Graphemes") {
					state.shimsUsed.set("std.Graphemes", true);
					if(name == "boundaries" && !RuntimeResidents.isResident(imports.selfModule)) {
						// Same routing as the path arm above: the boundary
						// vector crosses whole, so the business caller
						// reaches the element-casting adapter.
						imports.require("crate::runtime::graphemes");
						return "graphemes::boundaries";
					}
					imports.requireType("runtime.Graphemes", "Graphemes");
					return "Graphemes::" + RustImports.toSnakeCase(name);
				}
				for(field in cls.statics.get()) {
					if(field.name == name && field.kind.match(FVar(_, _)) && isFunctionType(field.type)) {
						final targetName = staticFunctionName(name);
						if(cls.module != imports.selfModule) {
							imports.requireType(cls.module, targetName);
						}
						return targetName;
					}
				}
				for(field in cls.statics.get()) {
					if(field.name == name && DataTableHelper.isDataTableField(field)) {
						if(cls.module == imports.selfModule) {
							return name;
						} else {
							imports.requireType(cls.module, name);
							return name;
						}
					}
				}
				if(markedField != null && (isDirectArrayStaticField(markedField) || isLazyArrayStaticField(markedField))) {
					return staticItemPath(cls, name);
				}
				imports.requireType(cls.module, cls.name);
				return cls.name + "::" + RustImports.toSnakeCase(name);
		}
	}

	function findStaticField(cls: ClassType, name: String): Null<ClassField> {
		for(field in cls.statics.get()) {
			if(field.name == name) return field;
		}
		return null;
	}

	/**
		Reference to the UString runtime through the std.UStringRT extern.
		A resident caller addresses the compiled class directly and shares
		its i32 convention; a business caller goes through the u32 adapter
		free functions emitted beside the class, because Null and Array
		results have no call-site cast machinery (RuntimeResidents).
	*/
	function uStringRef(name: String): String {
		state.shimsUsed.set("std.UStringRT", true);
		if(RuntimeResidents.isResident(imports.selfModule)) {
			imports.requireType("runtime.UString", "UString");
			return "UString::" + RustImports.toSnakeCase(name);
		}
		imports.require("crate::runtime::u_string");
		return "u_string::" + RustImports.toSnakeCase(name);
	}

	function typeExpr(t: ModuleType): String {
		switch(t) {
			case TClassDecl(c):
				final cls = c.get();
				if(cls.pack.length == 0 && (cls.name == "String" || cls.name == "Math")) {
					return cls.name;
				}
				if(cls.module == "std.Test" || (cls.pack.join(".") == "std" && (cls.name == "Test" || cls.name == "__test_shim"))) {
					state.shimsUsed.set("std.Test", true);
					imports.require("crate::runtime::test as testlib");
					return "testlib";
				}
				imports.requireType(cls.module, cls.name);
				return cls.name;
			case TEnumDecl(e):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				final name = owner != null ? owner : en.name;
				imports.requireType(en.module, name);
				return name;
			case _:
				Context.error("type expression has no value lowering", Context.currentPos());
				return null;
		}
	}

	function stdString(arg: TypedExpr, inConcat: Bool): String {
		return stdStringType(arg.t, expr(arg), inConcat, arg);
	}

	function stdIsOfType(args: Array<TypedExpr>): String {
		final target = TypeCheckHelper.classOfTypeExpr(args[1]);
		if(target == null) {
			Context.error("Std.isOfType requires a class type expression", args[1].pos);
			return "false";
		}
		final known = TypeCheckHelper.knownIsOfType(args[0], target);
		if(known != null) {
			return known ? "true" : "false";
		}
		return expr(args[0]) + ".__haxe_type_name() == \"" + target.module + "." + target.name + "\"";
	}

	function stdStringType(t: Type, value: String, inConcat: Bool, origin: TypedExpr, depth: Int = 0): String {
		return switch(Context.follow(t)) {
			case TInst(c, _) if(c.get().name == "String"):
				inConcat ? value : value + ".to_string()";
			case TInst(c, [element]) if(c.get().name == "Array"):
				imports.require("std::fmt::Write");
				final index = depth == 0 ? "i" : "i" + depth;
				final item = stdStringType(element, value + "[" + index + "]", true, origin, depth + 1);
				'{ let mut out = String::new(); out.push(\'[\'); let n = ${value}.len(); let mut ${index} = 0usize; while ${index} < n { if ${index} > 0 { out.push_str(", "); } let _ = write!(out, "{}", ${item}); ${index} += 1; } out.push(\']\'); out }';
			case TInst(c, _) if(StaticFieldHelper.hasSelfConstructionStatic(c.get()) || c.get().meta.has(":dataClass")): value + ".to_string()";
			case TAbstract(a, _) if(ValueTypeSupport.isMarkedAbstract(a.get())):
				ValueTypeSupport.memberField(a.get(), "toString") != null
					? value + ".to_string()"
					: value + ".0.to_string()";
			case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool"): inConcat ? value : value + ".to_string()";
			case TAbstract(a, params) if(a.get().module == "std.ReadOnlyArray"):
				stdStringType(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, inConcat, origin, depth);
			case TEnum(en, _) if(isParameterlessEnum(en.get())): value + ".name()" + (inConcat ? "" : ".to_string()");
			case TEnum(_, _): value + ".to_string()";
			case _:
				Context.error("Std.string accepts scalars, enum values, records, and arrays of them only", origin.pos);
				null;
		};
	}

	function isParameterlessEnum(en: EnumType): Bool {
		for(ef in en.constructs) switch(ef.type) {
			case TFun(args, _) if(args.length > 0): return false;
			case _:
		}
		return true;
	}

	function stdStringArg(e: TypedExpr): Null<TypedExpr> {
		return switch(stripWrap(e).expr) {
			case TCall({expr: TField(_, FStatic(c, cf))}, args) if(c.get().module == "Std" && cf.get().name == "string" && args.length == 1): args[0];
			case _: null;
		};
	}

	function stringToolsHex(args: Array<TypedExpr>): String {
		final value = args[0];
		final digits = args.length > 1 && !isTNull(args[1]) ? args[1] : null;
		if(isNegativeIntLiteral(value) || (digits != null && isNegativeIntLiteral(digits))) {
			Context.error("StringTools.hex accepts non-negative arguments only", value.pos);
		}
		final valueText = expr(value);
		if(digits == null) {
			return "format!(\"{:X}\", " + valueText + ")";
		}
		return "format!(\"{:0w$X}\", " + valueText + ", w = usize::try_from(" + expr(digits) + ").unwrap_or_default())";
	}

	function isNegativeIntLiteral(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(TInt(value)): value < 0;
			case TUnop(OpNeg, _, inner):
				switch(stripWrap(inner).expr) {
					case TConst(TInt(value)): value > 0;
					case _: false;
				}
			case _: false;
		};
	}

	/** Routes calls on a marked abstract implementation to Rust members. */
	function valueTypeCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
		switch(stripWrap(fn).expr) {
			case TField(_, FStatic(c, cf)):
				final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
				if(abs == null) return null;
				final field = cf.get();
				if(field.name == "_new") {
					imports.requireType(abs.module, abs.name);
					final rendered = ctorCallArgs(c.get(), args);
					if(ValueTypeSupport.constructorThrows(abs)) {
						final call = abs.name + "::new(" + rendered + ")";
						return call + (isFallible ? "?" : ".unwrap()");
					}
					return abs.name + "(" + rendered + ")";
				}
				if(field.name == "toString" && args.length > 0) return expr(args[0]) + ".to_string()";
				final op = ValueTypeSupport.operatorOf(abs, field);
				if(op != null) {
					return switch(op) {
						case Binary(_): args.length >= 2 ? expr(args[0]) + " " + opStrForValue(op) + " " + expr(args[1]) : abs.name;
						case Unary(_): args.length > 0 ? "-" + expr(args[0]) : abs.name;
					};
				}
				if(ValueTypeSupport.hasReceiver(field) && args.length > 0) {
					return expr(args[0]) + "." + RustImports.toSnakeCase(field.name) + "(" + [for(i in 1...args.length) expr(args[i])].join(", ") + ")";
				}
				return abs.name + "::" + RustImports.toSnakeCase(field.name) + "(" + [for(a in args) expr(a)].join(", ") + ")";
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
				if(abs == null) return null;
				final name = cf.get().name;
				return name == "toString" ? expr(subj) + ".to_string()" : expr(subj) + "." + RustImports.toSnakeCase(name) + "(" + [for(a in args) expr(a)].join(", ") + ")";
			case _:
		}
		return null;
	}

	function opStrForValue(op:ValueTypeOperator):String {
		return switch(op) {
			case Binary(binary): opStr(binary);
			case Unary(_): "-";
		};
	}

	function call(fn: TypedExpr, args: Array<TypedExpr>): String {
		final int64CallText = int64Call(fn, args);
		if(int64CallText != null) return int64CallText;
		final wrapperCall = valueTypeCall(fn, args);
		if(wrapperCall != null) return wrapperCall;
		switch(fn.expr) {
			case TField(_, FStatic(c, cf)) if(c.get().module == "Std" && cf.get().name == "string" && args.length == 1): return stdString(args[0], false);
			case TField(_, FStatic(c, cf)) if(c.get().module == "Std" && cf.get().name == "isOfType" && args.length == 2): return stdIsOfType(args);
			case TField(subj, FInstance(_, _, cf)) if(cf.get().name == "get_message" && args.length == 0):
				final target = stripWrap(subj);
				switch(target.expr) {
					case TLocal(v) if(catchVars.exists(v.id)):
						// Property getter on a caught exception: Display
						// carries the variant text (features/06).
						return "format!(\"{}\", " + RustImports.toSnakeCase(localName(v)) + ")";
					case _:
				}
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final name = cf.get().name;
				final path = cls.pack.join(".") + "." + cls.name;
				final markedField = findStaticField(cls, name);
				if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
					final isOwnedExtension = StaticFunctionMarkers.isExtension(markedField)
						&& RustDecl.isCrateOwnedReceiver(cls.module, args[0].t);
					final isStaticFallible = isFallibleCallee(c, cf, true);
					final q = isFallible ? (isStaticFallible ? "?" : "") : (isStaticFallible ? ".unwrap()" : "");
					if(isOwnedExtension) {
						final receiver = expr(args[0]);
						final receiverText = StringTools.startsWith(receiver, "*") ? "(" + receiver + ")" : receiver;
						return receiverText + "." + RustImports.toSnakeCase(name) + "("
							+ renderCallArgs(cf.get().type, args.slice(1), null, 1) + ")" + q;
					}
					return staticRef(cls, name) + "(" + renderCallArgs(cf.get().type, args) + ")" + q;
				}
				if((cls.name == "Functional" || cls.name == "__functional_shim" || path == "std.Functional" || cls.module == "std.Functional") && name == "sortedBy") {
					final receiver = args[0];
					final lambda = args[1];
					final func = unwrapLambda(lambda);
					if(func != null && func.args.length == 1) {
						final paramName = RustImports.toSnakeCase(func.args[0].v.name);
						final keyExpr = expr(lambdaBody(func.expr));
						return "{\n    let mut _sorted = " + expr(receiver) + ".to_vec();\n    _sorted.sort_by_key(|" + paramName + "| " + keyExpr + ");\n    _sorted\n}";
					}
				}
			case _:
		}
		final inlineMapCall = mapHasOwnPropertyCall(fn, args);
		if(inlineMapCall != null) {
			return inlineMapCall;
		}
		final renderedArgs = [for(a in args) expr(a)].join(", ");
		switch(fn.expr) {
			case TField(_, FStatic(c, cf)) if(c.get().module == "haxe.io.Bytes" && cf.get().name == "alloc" && args.length == 1):
				return "vec![0u8; " + expr(args[0]) + " as usize]";
			case TCast(inner, _):
				return call(inner, args);
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return expr(subj) + ".len() as u32";
			case TField(subj, FInstance(c, _, cf)):
				final name = cf.get().name;
				final staticGuard = staticGuardOf(subj);
				if(staticGuard != null) {
					if(name == "push" && args.length == 1) {
						return staticGuard + ".push(" + staticContainerArg(args[0]) + ")";
					}
					if(name == "length" || name == "get_length") {
						return rustU32Length(staticGuard + ".len()");
					}
				}
				if(isString(subj)) {
					if(name == "toLowerCase") return expr(subj) + ".to_lowercase()";
					if(name == "toUpperCase") return expr(subj) + ".to_uppercase()";
				}
				final snake = RustImports.toSnakeCase(name);
				if(isMapType(subj.t)) {
					if(name == "exists" && args.length == 1) return expr(subj) + ".contains_key(&" + rustMapKey(args[0]) + ")";
					if(name == "get" && args.length == 1) return expr(subj) + ".get(&" + rustMapKey(args[0]) + ").cloned()";
					if(name == "set" && args.length == 2) return expr(subj) + ".insert(" + rustMapKey(args[0]) + ", " + rustMapValue(args[1]) + ")";
				}
				if(isStringBuf(subj)) {
					// stdlib/08: add and addChar lower only as statements,
					// because the pairing check leaves through `return Err`.
					if(name == "add") {
						return fail(subj, "string buffer add has no expression lowering: keep the mutation a statement inside a fallible function (stdlib/08)");
					}
					if(name == "addChar") {
						return fail(subj, "string buffer addChar has no expression lowering: keep the mutation a statement inside a fallible function (stdlib/08)");
					}
					if(name == "toString") {
						final fault = stringBufFaultEnum();
						if(fault == null) {
							return fail(subj, "string buffer checks require std.UStringException in the module set (stdlib/08)");
						}
						// The unit vector keeps the buffer well-formed up to
						// a trailing lead, so from_utf16 fails exactly on
						// that lead and the map_err names it. The `?` or
						// `.unwrap()` rides the ordinary fallibility rules.
						final q = isFallible ? "?" : ".unwrap()";
						return "String::from_utf16(" + expr(subj) + ".as_slice()).map_err(|_| " + fault + "::UnpairedSurrogate { unit: "
							+ expr(subj) + "[" + expr(subj) + ".len() - 1] as u32 })" + q;
					}
					if(name == "get_length" || name == "length") {
						return expr(subj) + ".len() as u32";
					}
				}
				if(name == "get" && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + " as usize]";
				}
				if(name == "set" && args.length == 2 && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + " as usize] = " + expr(args[1]) + " as u8";
				}
				if(name == "blit" && args.length == 4 && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + " as usize..(" + expr(args[0]) + " + " + expr(args[3]) + ") as usize].copy_from_slice(&" + expr(args[1]) + "[" + expr(args[2]) + " as usize..(" + expr(args[2]) + " + " + expr(args[3]) + ") as usize])";
				}
				if(name == "fill" && args.length == 3 && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + " as usize..(" + expr(args[0]) + " + " + expr(args[1]) + ") as usize].fill(" + expr(args[2]) + " as u8)";
				}
				if(name == "sub" && args.length == 2 && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + " as usize..(" + expr(args[0]) + " + " + expr(args[1]) + ") as usize].to_vec()";
				}
				if(name == "charCodeAt" && isString(stripCast(subj))) {
					return expr(subj) + ".as_bytes()[(" + expr(args[0]) + ") as usize]";
				}
				if(name == "substring" && isString(stripCast(subj))) {
					// Member-call lowering into the u_string runtime: the
					// bounds are UTF-16 units on every target, so the call
					// converts them to byte boundaries. The runtime keeps
					// i32 bounds for the same clamping reason as
					// u_string.slice (SIGNED_SHIM_PARAMS), and the subject
					// borrows like every u_string call. An omitted
					// ?endIndex reaches this arm as a null argument and
					// routes to the one-sided form.
					state.shimsUsed.set("std.UStringRT", true);
					imports.require("crate::runtime::u_string");
					final endOmitted = args.length < 2 || switch(stripWrap(args[1]).expr) {
						case TConst(TNull): true;
						case _: false;
					};
					if(!endOmitted) {
						return "u_string::substring(&" + expr(subj) + ", (" + expr(args[0]) + ") as i32, (" + expr(args[1]) + ") as i32)";
					}
					return "u_string::substring_from(&" + expr(subj) + ", (" + expr(args[0]) + ") as i32)";
				}
				if(name == "put" && isSortedBuilder(subj)) {
					// Builder puts borrow every argument; the resident
					// clones into storage, so the call-site expressions
					// stay alive.
					final putArgs = [for(a in args) sortedRefArg(a)];
					return expr(subj) + ".put(" + putArgs.join(", ") + ")";
				}
				if((name == "get" || name == "has") && (isSortedTable(subj) || isSortedBuilder(subj))) {
					return expr(subj) + "." + name + "(" + sortedRefArg(args[0]) + ")";
				}
				if(name == "size" && isSortedTable(subj)) {
					// The resident counts in its signed Int domain; the
					// business domain is unsigned.
					return "(" + expr(subj) + ".size()) as u32";
				}
				if((name == "keyAt" || name == "valueAt" || name == "at") && isSortedTable(subj)) {
					return expr(subj) + "." + RustImports.toSnakeCase(name) + "((" + expr(args[0]) + ") as i32)";
				}
				if(name == "put" && isSortedBuilder(subj)) {
					final kExpr = switch(args[0].expr) {
						case TConst(TString(_)): expr(args[0]);
						case TLocal(_) | TField(_):
							if(!isTypeCopy(args[0].t)) {
								expr(args[0]) + ".clone()";
							} else {
								expr(args[0]);
							}
						case _: expr(args[0]);
					};
					if(args.length > 1) {
						final vExpr = if(isStringType(args[1].t)) {
							switch(args[1].expr) {
								case TConst(TString(_)): expr(args[1]) + ".to_string()";
								case _: expr(args[1]) + ".clone()";
							}
						} else {
							expr(args[1]);
						};
						return expr(subj) + ".put(" + kExpr + ", " + vExpr + ")";
					} else {
						return expr(subj) + ".put(" + kExpr + ")";
					}
				}
				if((name == "get" || name == "has") && (isSortedTable(subj) || isSortedBuilder(subj))) {
					final kExpr = if(isStringType(args[0].t)) {
						switch(args[0].expr) {
							case TConst(TString(_)): expr(args[0]);
							case TLocal(v):
								final pt = types.of(v.t, true);
								if(pt == "&str") expr(args[0]); else "&" + expr(args[0]);
							case _: expr(args[0]);
						}
					} else if(!isTypeCopy(args[0].t)) {
						"&" + expr(args[0]);
					} else {
						expr(args[0]);
					};
					return expr(subj) + "." + name + "(" + kExpr + ")";
				}
				if(name == "push") {
					return expr(subj) + ".push(" + renderPushArg(args[0]) + ")";
				}
				if(name == "join") {
					return expr(subj) + ".join(" + renderedArgs + ")";
				}
				if(name == "addByte") {
					return expr(subj) + ".add_byte((" + expr(args[0]) + ") as u8)";
				}
				if(name == "readU16") {
					// The wire read answers u16 while the Int domain is
					// u32; the widening is total, so from covers every
					// value the field can hold. The read is fallible, so
					// the call propagates before the widening.
					return "u32::from(" + expr(subj) + ".read_u16()?)";
				}
				if(name == "writeU16") {
					// The Int domain is u32 while the wire field is u16;
					// the Haxe writer masks to the low half, and the Rust
					// cast truncates identically, so the narrowing matches
					// source semantics for every value.
					return expr(subj) + ".write_u16((" + expr(args[0]) + ") as u16)";
				}
				if(name == "writeU32") {
					final innerArg = stripWrap(args[0]);
					final isLen = switch(innerArg.expr) {
						case TField(_, fa) if(fieldName(fa) == "length"): true;
						case _: false;
					};
					if(isLen) {
						if(errorTypeName == null || countOverflowVariant == null) {
							Context.error("cannot lower length conversion: missing error enum or overflow variant", args[0].pos);
							return "";
						}
						final errVariant = errorTypeName + "::" + countOverflowVariant;
						return expr(subj) + ".write_u32(u32::try_from(" + expr(args[0]) + ").map_err(|_| " + errVariant + ")?)";
					}
					return expr(subj) + ".write_u32(" + expr(args[0]) + ")";
				}
				if(name == "writeAscii") {
					// A heap String argument borrows as &str; string
					// literals and parameters of the enclosing function
					// already render as &str.
					final argStr = if(isStringType(args[0].t)) {
						switch(stripWrap(args[0]).expr) {
							case TConst(TString(_)): expr(args[0]);
							case TLocal(v) if(paramVarIds.get(v.id) == true): expr(args[0]);
							case _: expr(args[0]) + ".as_str()";
						}
					} else {
						expr(args[0]);
					};
					return expr(subj) + ".write_ascii(" + argStr + ")";
				}
				if(cf != null && cf.get().kind.match(FVar(_, _)) && Context.follow(cf.get().type).match(TFun(_, _))) {
					// A function-typed field calls through a parenthesized
					// receiver: the field itself names the callee, so the
					// read renders as an explicit field access in the
					// parenthesized position. Method fields (FMethod) take
					// the ordinary method-call path above this branch.
					// Parameter-typed arguments borrow unless the local
					// already holds a reference (a borrowed parameter of
					// the enclosing function).
					return "(" + expr(subj) + "." + snake + ")(" + renderCallArgs(cf.get().type, args) + ")";
				}
				final isMethodFallible = isFallibleCallee(c, cf, false);
				final q = isFallible ? (isMethodFallible ? "?" : "") : (isMethodFallible ? ".unwrap()" : "");
				// A nullable receiver renders through the same optional
				// unwrap as a plain field read: the field lowers to an
				// Option while the method resolves on the inner type.
				final subjStr = isNullType(subj.t) ? expr(subj) + ".as_ref().unwrap()" : expr(subj);
				return subjStr + "." + snake + "(" + renderCallArgs(cf.get().type, args) + ")" + q;
			case TField(_, FStatic(c, cf)):
				final cls = c.get();
				final name = cf.get().name;
				final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
				if(cls.pack.length == 0 && cls.name == "StringTools" && name == "hex") {
					return stringToolsHex(args);
				}
				if(cls.pack.length == 0 && cls.name == "StringTools" && name == "trim" && args.length == 1) {
					return expr(args[0]) + ".trim()";
				}
				if(cls.pack.length == 0 && cls.name == "Std" && name == "int") {
					// An Int-typed argument converts nothing, except a
					// bare length read, whose rendering is usize; Float
					// arguments and those lengths still cross through
					// the cast.
					if(isIntType(args[0].t) && !isUsizeExpr(args[0])) {
						return expr(args[0]);
					}
					// Haxe types Int/Int division as Float, but the
					// length-division lowering renders it as
					// truncating integer division; Std.int over it
					// converts nothing.
					if(isLengthDivision(args[0])) {
						return "(" + expr(args[0]) + ")";
					}
					return "(" + expr(args[0]) + ") as i32";
				}
				if(cls.pack.length == 0 && cls.name == "String" && name == "fromCharCode") {
					return "String::from_utf16(&[u16::try_from(" + expr(args[0]) + ").unwrap_or_default()]).unwrap_or_default()";
				}
				if(path == "std.UStringPlatform") {
					// Cursor primitives of the resident UString walk, inlined
					// per call: a cursor is a byte offset here, so end is the
					// byte length, codeAt decodes the char at the offset, and
					// advance adds that char's UTF-8 width. Business code
					// never reaches them; it calls std.UString.
					if(!RuntimeResidents.isResident(imports.selfModule)) {
						Context.error("std.UStringPlatform is a resident runtime primitive; business code calls std.UString", fn.pos);
					}
					switch(name) {
						case "end":
							return "(" + expr(args[0]) + ").len() as i32";
						case "codeAt":
							return "(" + expr(args[0]) + ")[(" + expr(args[1]) + ") as usize..].chars().next().unwrap_or('\\0') as i32";
						case "advance":
							return "((" + expr(args[1]) + ") as usize + (" + expr(args[0]) + ")[(" + expr(args[1]) + ") as usize..].chars().next().unwrap_or('\\0').len_utf8()) as i32";
						case "substringBetween":
							return "(" + expr(args[0]) + ")[(" + expr(args[1]) + ") as usize..(" + expr(args[2]) + ") as usize].to_string()";
						case "fromCodePoint":
							return "char::from_u32((" + expr(args[0]) + ") as u32).unwrap_or('\\0').to_string()";
						case _:
					}
				}
				if(path == "std.TestPlatform") {
					// Host edges of the resident runtime.TestCore, inlined
					// per call: raising is a panic, the running test id
					// lives in the test host module of the runtime emit, and
					// plain numbers render through to_string. Marking the
					// std.Test shim used keeps that host module emitted
					// beside this resident. Business code never reaches
					// these; it calls std.Test.
					if(!RuntimeResidents.isResident(imports.selfModule)) {
						Context.error("std.TestPlatform is a resident runtime primitive; business code calls std.Test", fn.pos);
					}
					state.shimsUsed.set("std.Test", true);
					switch(name) {
						case "raise":
							return "panic!(\"{}\", " + expr(args[0]) + ")";
						case "currentTestId":
							return "crate::runtime::test::current_test_id()";
						case "intToString":
							return "(" + expr(args[0]) + ").to_string()";
						case "floatToString":
							return "(" + expr(args[0]) + ").to_string()";
						case _:
					}
				}
				if(path == "haxe.io.FPHelper") {
					imports.requireType(cls.module, "FPHelper");
					// The f32 configuration converts the two 64-bit value edges to their
					// binary32 runtime variants; the 8-byte wire bit layout
					// is untouched (feature spec 23, ruling 7).
					final targetName = if(FloatPrecision.isF32()) {
						if(name == "i64ToDouble") "i64ToF32" else if(name == "doubleToI64") "f32ToI64" else name;
					} else {
						name;
					}
					return "FPHelper::" + RustImports.toSnakeCase(targetName) + "(" + renderedArgs + ")";
				}
				if(cls.module == "Math" && name == "isNaN") return "(" + expr(args[0]) + ").is_nan()";
				if(cls.module == "Math" && name == "isFinite") return "(" + expr(args[0]) + ").is_finite()";
				if(cls.module == "Std" && name == "parseFloat") {
					final real = FloatPrecision.isF32() ? "f32" : "f64";
					final nan = FloatPrecision.isF32() ? "f32::NAN" : "f64::NAN";
					return "{ let t = (" + expr(args[0]) + ").trim_matches(|c: char| matches!(c, ' ' | '\\t' | '\\n' | '\\u{0B}' | '\\u{0C}' | '\\r')); let b = t.as_bytes(); let valid = { let mut i = 0; if i < b.len() && (b[i] == b'+' || b[i] == b'-') { i += 1; } let start = i; while i < b.len() && b[i].is_ascii_digit() { i += 1; } let before = i > start; if i < b.len() && b[i] == b'.' { i += 1; while i < b.len() && b[i].is_ascii_digit() { i += 1; } } let after = before || (!before && i > start + 1); if !before && !after { false } else if i < b.len() && (b[i] == b'e' || b[i] == b'E') { i += 1; if i < b.len() && (b[i] == b'+' || b[i] == b'-') { i += 1; } let exponent_start = i; while i < b.len() && b[i].is_ascii_digit() { i += 1; } i > exponent_start && i == b.len() } else { i == b.len() } }; if valid { t.parse::<" + real + ">().unwrap_or(" + nan + ") } else { " + nan + " } }";
				}
				if(cls.module == "Std" && name == "parseInt") {
					return "{ let t = (" + expr(args[0]) + ").trim_matches(|c: char| matches!(c, ' ' | '\\t' | '\\n' | '\\u{0B}' | '\\u{0C}' | '\\r')); let (negative, d) = if t.starts_with('-') { (true, &t[1..]) } else if t.starts_with('+') { (false, &t[1..]) } else { (false, t) }; if d.starts_with(\"0x\") || d.starts_with(\"0X\") { match i64::from_str_radix(&d[2..], 16) { Ok(n) => { let n = if negative { -n } else { n }; if n >= -2147483648 && n <= 2147483647 { Some(n as i32) } else { None } }, Err(_) => None } } else if !negative { match t.parse::<i64>() { Ok(n) => if n <= 2147483647 { Some(n as i32) } else { None }, Err(_) => None } } else { match t.parse::<i64>() { Ok(n) => if n >= -2147483648 { Some(n as i32) } else { None }, Err(_) => None } } }";
				}
				if(cls.pack.join(".") == "std" && cls.name == "Process" && name == "exit") {
					imports.require("std::process::exit");
					return "exit(" + renderedArgs + ")";
				}
				if((path == "std.SortedMap" || cls.module == "std.SortedMap") && name == "builder") {
					final kType = sortedKeyType(fn);
					final vType = sortedValueType(fn);
					state.shimsUsed.set("std.SortedMap", true);
					imports.requireType("runtime.SortedTable", "SortedTable");
					return "SortedTable::map_builder::<" + types.of(kType) + ", " + types.of(vType) + ">(" + sortedComparator(kType, fn.pos) + ")";
				}
				if((path == "std.SortedSet" || cls.module == "std.SortedSet") && name == "builder") {
					final kType = sortedKeyType(fn);
					state.shimsUsed.set("std.SortedSet", true);
					imports.requireType("runtime.SortedTable", "SortedTable");
					return "SortedTable::set_builder::<" + types.of(kType) + ">(" + sortedComparator(kType, fn.pos) + ")";
				}

				
				if(cls.module == "std.Test" || (cls.pack.join(".") == "std" && (cls.name == "Test" || cls.name == "__test_shim"))) {
					// The assertion checks and message formatting live in the
					// resident runtime.TestCore; this host module keeps run and
					// its result recording. Messages are plain &str: an absent
					// message renders as the empty string, which the canonical
					// builder omits.
					state.shimsUsed.set("std.Test", true);
					imports.require("crate::runtime::test as testlib");
					imports.require("crate::runtime::test_core");
					final messageArg = function(idx: Int): String {
						return (args.length > idx && !isTNull(args[idx])) ? "&(" + expr(args[idx]) + ")" : "\"\"";
					};
					if(name == "ok") {
						final cond = expr(args[0]);
						return "test_core::TestCore::ok(" + cond + ", " + messageArg(1) + ")";
					}
					if(name == "fail") {
						return "test_core::TestCore::fail(&(" + expr(args[0]) + "))";
					}
					if(name == "run") {
						return "testlib::run(" + renderedArgs + ")";
					}
					if(name == "equals") {
						final expectedArg = args[0];
						final actualArg = args[1];
						final msg = messageArg(2);
						if(isNullType(expectedArg.t) || isNullType(actualArg.t)) {
							final nullInner = getNullInnerType(expectedArg.t != null && isNullType(expectedArg.t) ? expectedArg.t : actualArg.t);
							final innerKind = scalarTypeKind(nullInner);
							imports.require("crate::tests::test_helper::*");
							switch(innerKind) {
								case "String":
									final expStr = renderOptArg(expectedArg, "String");
									final actStr = renderOptArg(actualArg, "String");
									return "assert_equals_opt_string(&" + expStr + ", &" + actStr + ", " + msg + ")";
								case "Int":
									final expStr = renderOptArg(expectedArg, "Int");
									final actStr = renderOptArg(actualArg, "Int");
									return "assert_equals_opt(&" + expStr + ", &" + actStr + ", " + msg + ")";
								case _:
							}
						}
						if(isScalarType(expectedArg.t)) {
							final scalarKind = scalarTypeKind(expectedArg.t);
							switch(scalarKind) {
								case "Bool":
									return "test_core::TestCore::equals_bool(" + expr(expectedArg) + ", " + expr(actualArg) + ", " + msg + ")";
								case "Int":
									// Business Int renders u32, usize in loop heads;
									// the resident takes i32, so both sides cast once.
									return "test_core::TestCore::equals_int((" + expr(expectedArg) + ") as i32, (" + expr(actualArg) + ") as i32, " + msg + ")";
								case "Float":
									return "test_core::TestCore::equals_float(" + expr(expectedArg) + ", " + expr(actualArg) + ", " + msg + ")";
								case "String":
									return "test_core::TestCore::equals_string(&(" + expr(expectedArg) + "), &(" + expr(actualArg) + "), " + msg + ")";
								case _:
							}
						}
						// Aggregate equality
						recordAggregateType(expectedArg.t);
						final fnName = aggregateAssertFuncName(expectedArg.t);
						imports.require("crate::tests::test_helper::*");
						return fnName + "(&" + expr(expectedArg) + ", &" + expr(actualArg) + ", " + msg + ")";
					}
				}
				final isStaticFallible = isFallibleCallee(c, cf, true);
				final q = isFallible ? (isStaticFallible ? "?" : "") : (isStaticFallible ? ".unwrap()" : "");
				final shimKey = if(cls.module == "std.UStringRT") {
					"u_string." + name;
				} else {
					null;
				};
				var signedPositions = shimKey != null ? SIGNED_SHIM_PARAMS.get(shimKey) : null;
				final callerResident = RuntimeResidents.isResidentAbi(imports.selfModule);
				// std.UStringRT resolves by caller: residents reach the
				// i32 class, business reaches the u32 adapters, so the
				// callee convention always matches the resolved path.
				final calleeResident = cls.module == "std.UStringRT"
					? callerResident
					: RuntimeResidents.isResidentAbi(cls.module);
				if(calleeResident) {
					// Resident runtime modules render haxe Int as i32
					// (their clamping contracts carry negative values),
					// while business expressions render u32; every Int
					// parameter casts once at the call boundary.
					signedPositions = intParamPositions(cf.get().type);
				}
				final callStr = staticRef(cls, name) + "(" + renderCallArgs(cf.get().type, args, signedPositions) + ")" + q;
				if(calleeResident != callerResident && returnsInt(cf.get().type)) {
					// An Int result crosses between the two conventions;
					// containers never cross whole, only their elements
					// through Int-typed expressions, which the argument
					// casts above already cover.
					return "(" + callStr + ") as " + (callerResident ? "i32" : "u32");
				}
				return callStr;
			case TField(subj, FEnum(e, ef)):
				final en = e.get();
				imports.requireType(en.module, en.name);
				final efArgs = switch(ef.type) {
					case TFun(fargs, _): fargs;
					case _: [];
				};
				final parts = [];
				for(i in 0...args.length) {
					final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
					parts.push(argName + ": " + expr(args[i]));
				}
				if(parts.length == 0) {
					return en.name + "::" + ef.name;
				}
				return en.name + "::" + ef.name + " { " + parts.join(", ") + " }";
			case TConst(TSuper):
				return "super(" + renderedArgs + ")";
			case TLocal(_):
				return expr(fn) + "(" + renderCallArgs(fn.t, args) + ")";
			case _:
				return expr(fn) + "(" + renderedArgs + ")";
		}
	}

	function functionLiteral(f: TFunc, functionType: Null<Type>): String {
		final params = [for(a in f.args) RustImports.toSnakeCase(a.v.name)].join(", ");
		final previousReturnUnsigned = returnUnsigned;
		final previousReturnTypeName = returnTypeName;
		final previousReturnType = currentReturnType;
		final functionReturn = switch(functionType) {
			case null: null;
			case _: switch(Context.follow(functionType)) {
				case TFun(_, ret): ret;
				case _: null;
			}
		};
		returnUnsigned = functionReturn == null ? false : switch(Context.follow(functionReturn)) {
			case TAbstract(a, _) if(a.get().name == "Int"): !RuntimeResidents.isResident(imports.selfModule);
			case _: false;
		};
		returnTypeName = functionReturn == null ? null : types.of(functionReturn, false);
		currentReturnType = functionReturn;
		final body = coalescingNormalizationLines(f.expr, 2, [for(a in f.args) a.v.name]).concat(blockLines(statementsOf(f.expr), 2, true));
		returnUnsigned = previousReturnUnsigned;
		returnTypeName = previousReturnTypeName;
		currentReturnType = previousReturnType;
		return 'move |$params| {\n' + body.join("\n") + '\n}';
	}

	function functionValueLiteral(f: TFunc, functionType: Null<Type>): String {
		return "Box::new(" + functionLiteral(f, functionType) + ")";
	}

	function functionLiteralNamed(name: String, f: TFunc, functionType: Null<Type>): String {
		final previous = currentLocalName;
		currentLocalName = name;
		final result = functionLiteral(f, functionType);
		currentLocalName = previous;
		return result;
	}

	function functionValueLiteralNamed(name: String, f: TFunc, functionType: Null<Type>): String {
		final previous = currentLocalName;
		currentLocalName = name;
		final result = functionValueLiteral(f, functionType);
		currentLocalName = previous;
		return result;
	}

	function isFallibleCallee(c: Ref<ClassType>, cf: Ref<ClassField>, isStatic: Bool): Bool {
		final name = cf.get().name;
		if(RustEmissionState.runtimeShimIsFallible(name)) return true;
		return state.funcErrorEnums.exists(RustEmissionState.funcKey(c.get().module, name, isStatic));
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) {
			imports.requireType(valueType.module, valueType.name);
			final rendered = ctorCallArgs(cls, args);
			if(ValueTypeSupport.constructorThrows(valueType)) {
				return valueType.name + "::new(" + rendered + ")" + (isFallible ? "?" : ".unwrap()");
			}
			return valueType.name + "(" + rendered + ")";
		}
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return "Vec::<u16>::new()";
			case "haxe.ds._Map.Map_Impl_":
				imports.require("std::collections::HashMap");
				return "HashMap::new()";
			case "haxe.io.BytesBuffer":
				imports.requireType(path, "BytesBuffer");
				return "BytesBuffer::new()";
			case "Array":
				return "Vec::new()";
			case _:
				if(args.length == 1 && state.exceptionPayloads.exists(cls.module)) {
					return exceptionVariant(cls, args[0]);
				}
				imports.requireType(cls.module, cls.name);
				// The generic resident tables construct with explicit
				// type arguments: the empty-array arguments leave the
				// parameters otherwise unconstrained.
				final genericStr = params.length > 0 ? "::<" + [for(p in params) types.of(p)].join(", ") + ">" : "";
				// A throwing constructor lowers through the fallibility
				// machinery: `?` propagates inside a fallible function or
				// a try-region closure, and an infallible context
				// unwraps (feature spec 27).
				final ctorFallible = state.funcErrorEnums.exists(RustEmissionState.funcKey(cls.module, "new", false));
				final q = ctorFallible ? (isFallible ? "?" : ".unwrap()") : "";
				return cls.name + genericStr + "::new(" + ctorCallArgs(cls, args) + ")" + q;
		}
	}

	function isMapType(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TInst(def, params) if(def.get().pack.join(".") == "haxe" && def.get().name == "IMap" && params.length == 2): true;
			case TInst(def, _): isMapImplementation(def.get());
			case TType(def, params): def.get().pack.length == 0 && def.get().name == "Map" && params.length == 2;
			case TAbstract(def, params) if(def.get().pack.join(".") == "haxe.ds" && def.get().name == "Map" && params.length == 2): true;
			case TAbstract(a, params) if(a.get().name == "Null" && params.length == 1): isMapType(params[0]);
			case _: false;
		};
	}

	function isMapImplementation(cls: ClassType): Bool {
		return cls.pack.join(".") == "haxe.ds" && ["StringMap", "IntMap", "ObjectMap", "HashMap"].indexOf(cls.name) >= 0;
	}

	function mapBackingReceiver(e: TypedExpr): Null<TypedExpr> {
		return switch(stripWrap(e).expr) {
			case TField(receiver, FInstance(_, _, cf)) if(cf.get().name == "h" && isMapBackingType(receiver.t)): receiver;
			case TField(receiver, FAnon(cf)) if(cf.get().name == "h" && isMapBackingType(receiver.t)): receiver;
			case _: null;
		};
	}

	function isMapBackingType(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TInst(def, _):
				final cls = def.get();
				isMapImplementation(cls);
			case _: false;
		};
	}

	function mapAssignment(e: TypedExpr): Null<{receiver: TypedExpr, key: TypedExpr}> {
		return switch(stripWrap(e).expr) {
			case TArray(arr, key):
				final receiver = mapBackingReceiver(arr);
				receiver == null ? null : {receiver: receiver, key: key};
			case _: null;
		};
	}

	function isHasOwnPropertyValue(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TField(_, FInstance(_, _, cf)) | TField(_, FAnon(cf)) if(cf.get().name == "hasOwnProperty"): true;
			case _: false;
		};
	}

	function mapHasOwnPropertyCall(fn: TypedExpr, args: Array<TypedExpr>): Null<String> {
		if(args.length != 2) return null;
		return switch(stripWrap(fn).expr) {
			case TField(subject, FInstance(_, _, cf)) if(cf.get().name == "call" && isHasOwnPropertyValue(subject)):
				final receiver = mapBackingReceiver(args[0]);
				receiver == null ? null : expr(receiver) + ".contains_key(&" + rustMapKey(args[1]) + ")";
			case _: null;
		};
	}

	function rustMapKey(e: TypedExpr): String {
		final rendered = expr(e);
		return isStringType(e.t) || isStringLiteral(e) ? rendered + ".to_string()" : rendered;
	}

	function isStringLiteral(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(TString(_)): true;
			case _: false;
		};
	}

	function rustMapValue(e: TypedExpr): String {
		final rendered = expr(e);
		return isStringType(e.t) ? switch(stripWrap(e).expr) {
			case TConst(TString(_)): rendered + ".to_string()";
			case _: rendered;
		} : rendered;
	}

	/**
		Constructor arguments (feature spec 27): a String parameter takes
		&str, so a heap String argument borrows through .as_str() while a
		literal keeps its own static borrowing and a parameter of the
		enclosing function is already &str (`.as_str()` on &str is
		unstable); every other parameter renders as the plain expression,
		the convention the resident tables already construct under.
	**/
	function ctorCallArgs(cls: ClassType, args: Array<TypedExpr>): String {
		final fnType = cls.constructor != null ? cls.constructor.get().type : null;
		final paramTypes = fnType != null ? switch(Context.follow(fnType)) {
			case TFun(pargs, _): [for(p in pargs) p.t];
			case _: [];
		} : [];
		final out: Array<String> = [];
		for(i in 0...args.length) {
			final arg = args[i];
			final argStr = expr(arg);
			if(i < paramTypes.length) {
				final pt = paramTypes[i];
				if(isNullType(pt) && !isNullType(arg.t)) {
					// A nullable constructor parameter takes an Option; a
					// null literal already renders None, any other
					// argument wraps.
					if(argStr != "None") {
						final inner = switch(stripWrap(arg).expr) {
							case TConst(TString(s)): quoteString(s) + ".to_string()";
							case _: argStr;
						};
						out.push("Some(" + inner + ")");
						continue;
					}
					out.push(argStr);
					continue;
				}
				if(isInterfaceType(pt)) {
					out.push(renderValueForType(pt, arg, argStr));
					continue;
				}
				if(isStringType(pt) && isStringType(arg.t)) {
					out.push(switch(stripWrap(arg).expr) {
						case TConst(TString(_)): argStr;
						case TLocal(v) if(paramVarIds.get(v.id) == true): argStr;
						case _: argStr + ".as_str()";
					});
					continue;
				}
			}
			out.push(argStr);
		}
		return out.join(", ");
	}

	function numericAssignmentValue(expected: Type, actual: TypedExpr, rendered: String): String {
		if(!isIntType(expected) || !isIntType(actual.t)) return rendered;
		final target = types.of(expected, false);
		return target == "u32" || target == "i32" || target == "u8" ? "(" + rendered + ") as " + target : rendered;
	}

	function assignTarget(e: TypedExpr): String {
		switch(e.expr) {
			case TArray(arr, idx):
				return expr(arr) + "[(" + expr(idx) + ") as usize]";
			case TField(_, FStatic(c, cf)):
				final target = staticAssignmentTarget(e);
				return target != null ? target : staticRef(c.get(), cf.get().name);
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				return expr(subj) + "." + RustImports.toSnakeCase(cf.get().name);
			case TLocal(v):
				return RustImports.toSnakeCase(localName(v));
			case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
				return assignTarget(inner);
			case _:
				return fail(e, "assignment target has no Rust lowering: " + Std.string(e.expr));
		}
	}

	function objectLiteral(e: TypedExpr, fields: Array<{name: String, expr: TypedExpr}>): String {
		final typeName = resolveTypeName(e.t);
		final parts = [for(f in fields) {
			final val = if(isStringType(f.expr.t)) {
				switch(stripWrap(f.expr).expr) {
					case TConst(TString(_)): expr(f.expr) + ".to_string()";
					case TLocal(v) if(paramVarIds.exists(v.id)): expr(f.expr) + ".to_string()";
					case _: expr(f.expr) + ".clone()";
				}
			} else {
				expr(f.expr);
			};
			RustImports.toSnakeCase(f.name) + ": " + val;
		}];
		return typeName + " { " + parts.join(", ") + " }";
	}

	function resolveTypeName(t: Type): String {
		return switch(t) {
			case TType(def, _):
				final d = def.get();
				imports.requireType(d.module, d.name);
				d.name;
			case TAnonymous(anon):
				final match = state.structTypedefs.get(RustDecl.structureSignature(anon));
				if(match == null) {
					Context.error("anonymous structure literal has no matching named typedef", Context.currentPos());
					null;
				} else {
					imports.requireType(match.module, match.name);
					match.name;
				}
			case _:
				Context.error("object literal must be typed by a named typedef before translation", Context.currentPos());
				null;
		}
	}

	// ------------------------------------------------------------------
	// Local analysis
	// ------------------------------------------------------------------

	function scanLocals(e: TypedExpr): Void {
		switch(e.expr) {
			case TVar(v, init):
				if(v.name != "`") {
					usedNames.set(v.name, true);
				}
				if(init != null) {
					// Wire reads and reader positions arrive as unsigned values;
					// remember the locals so negative-domain checks lower as
					// upper-bound checks.
					switch(stripWrap(init).expr) {
						case TCall(fn, _):
							if(isFpHelperInt64Call(fn)) fpInt64Halves.set(v.id, true);
							switch(fn.expr) {
								case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
									final n = cf.get().name;
									if(n == "readU16" || n == "readU32" || n == "remaining" || n == "consumed") {
										unsignedLocals.set(v.id, true);
									}
								case _:
							}
						case _:
					}
				}
			case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
				switch(t.expr) {
					case TLocal(v):
						mutated.set(v.id, true);
					case TArray(arr, _):
						final receiver = mapBackingReceiver(arr);
						switch(stripWrap(receiver == null ? arr : receiver).expr) {
							case TLocal(v):
								mutated.set(v.id, true);
							case _:
						}
					case _:
				}
			case TCall(fn, args):
				switch(fn.expr) {
					case TField(subj, FInstance(_, _, cf)):
						final n = cf.get().name;
						if(n == "readU16" || n == "readU32" || n == "readF64" || n == "readAscii"
							|| n == "writeU16" || n == "writeU32" || n == "writeF64" || n == "writeAscii"
								|| n == "addByte" || n == "push" || n == "finish" || n == "put" || n == "set"
							|| n == "add" || n == "addChar") {
							switch(stripWrap(subj).expr) {
								case TLocal(v):
									mutated.set(v.id, true);
								case _:
							}
						}
					case _:
				}
				final isInstancePush = switch(fn.expr) {
					case TField(_, FInstance(_, _, cf)) if(cf.get().name == "push"): true;
					default: false;
				};
				if(!isInstancePush) {
					final paramTypes = switch(Context.follow(fn.t)) {
						case TFun(pargs, _): [for(p in pargs) p.t];
						default: [];
					};
					for(i in 0...args.length) {
						if(i < paramTypes.length) {
							if(isPassByRef(paramTypes[i])) {
								final isArray = switch(Context.follow(paramTypes[i])) {
									case TInst(c, _) if(c.get().name == "Array"): true;
									default: false;
								};
								if(isArray) {
									switch(stripWrap(args[i]).expr) {
										case TLocal(v):
											mutated.set(v.id, true);
										default:
									}
								}
							}
						}
					}
				}
			case _:
		}
		TypedExprTools.iter(e, scanLocals);
	}

	function mentionsLocal(e: TypedExpr, v: TVar): Bool {
		var found = false;
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TLocal(l) if(l.id == v.id): found = true;
				case _:
			}
			TypedExprTools.iter(x, walk);
		}
		walk(e);
		return found;
	}

	function localName(v: TVar): String {
		if(v.name != "`") {
			return v.name;
		}
		if(hiddenNames.exists(v.id)) {
			return hiddenNames.get(v.id);
		}
		final candidates = ["i", "j", "k", "n", "m", "index", "write", "read"];
		final taken: Map<String, Bool> = [];
		for(name in hiddenNames) taken.set(name, true);
		for(c in candidates) {
			if(!usedNames.exists(c) && !taken.exists(c)) {
				hiddenNames.set(v.id, c);
				return c;
			}
		}
		hiddenCounter += 1;
		final generated = "t" + hiddenCounter;
		hiddenNames.set(v.id, generated);
		return generated;
	}

	public function payloadName(ef: EnumField, index: Int): String {
		return switch(ef.type) {
			case TFun(args, _) if(index < args.length):
				RustImports.toSnakeCase(args[index].name);
			case _:
				"param" + index;
		};
	}

	// ------------------------------------------------------------------
	// Helpers
	// ------------------------------------------------------------------

	function symbolOf(op: Binop): String {
		return switch(op) {
			case OpAdd: "+";
			case OpMult: "*";
			case OpDiv: "/";
			case OpSub: "-";
			case OpEq: "==";
			case OpNotEq: "!=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpMod: "%";
			case OpAnd: "&";
			case OpOr: "|";
			case OpXor: "^";
			case OpShl: "<<";
			case OpShr: ">>";
			case _: fail(null, "operator symbol has no Rust lowering: " + Std.string(op));
		}
	}

	function precedenceOf(op: Binop): Int {
		return switch(op) {
			case OpMult | OpDiv | OpMod: 11;
			case OpAdd | OpSub: 10;
			case OpShl | OpShr | OpUShr: 9;
			case OpLt | OpLte | OpGt | OpGte: 8;
			case OpEq | OpNotEq: 7;
			case OpAnd: 6;
			case OpXor: 5;
			case OpOr: 4;
			case OpBoolAnd: 3;
			case OpBoolOr: 2;
			case OpAssign | OpAssignOp(_): 1;
			case _: 0;
		}
	}

	function associative(op: Binop): Bool {
		return switch(op) {
			case OpAdd | OpMult | OpAnd | OpOr | OpXor | OpBoolAnd | OpBoolOr: true;
			case _: false;
		}
	}

	function stripWrap(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): stripWrap(inner);
			case _: e;
		}
	}

			function unwrapLambda(e: TypedExpr): Null<TFunc> {
		if(e == null) return null;
		return switch(e.expr) {
			case TFunction(f): f;
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): unwrapLambda(inner);
			case _: null;
		};
	}

	function lambdaBody(e: TypedExpr): TypedExpr {
		if(e == null) return e;
		return switch(e.expr) {
			case TBlock(stmts) if(stmts.length > 0): lambdaBody(stmts[stmts.length - 1]);
			case TReturn(ret) if(ret != null): lambdaBody(ret);
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): lambdaBody(inner);
			case _: e;
		};
	}

	function stripCast(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TCast(inner, _) | TMeta(_, inner): stripCast(inner);
			case _: e;
		}
	}

	function fieldName(fa: FieldAccess): String {
		return switch(fa) {
			case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf) | FClosure(_, cf): cf.get().name;
			case FEnum(_, ef): ef.name;
			case FDynamic(n): n;
		}
	}

	function isBytes(e: TypedExpr): Bool {
		return switch(e.t) {
			case TInst(c, _): c.get().module == "haxe.io.Bytes";
			case TType(d, _): d.get().module == "haxe.io.Bytes";
			case _: false;
		}
	}

	function isString(e: TypedExpr): Bool {
		return switch(e.t) {
			case TInst(c, _): c.get().name == "String";
			case _: false;
		}
	}

	function quoteString(s: String): String {
		final esc = s.split("\\").join("\\\\").split("\"").join("\\\"").split("\n").join("\\n").split("\r").join("\\r").split("\t").join("\\t");
		return '"' + esc + '"';
	}

	function indent(depth: Int): String {
		var s = "";
		for(_ in 0...depth) s += "    ";
		return s;
	}

	function matchingParens(s: String): Bool {
		var depth = 0;
		for(i in 0...s.length) {
			if(s.charAt(i) == "(") depth++;
			else if(s.charAt(i) == ")") {
				depth--;
				if(depth == 0 && i < s.length - 1) return false;
			}
		}
		return depth == 0;
	}

	function fail(e: Null<TypedExpr>, msg: String): String {
		final pos = e != null ? e.pos : Context.currentPos();
		Context.error(msg, pos);
		return "";
	}

	function collectOrTerms(e: TypedExpr, out: Array<TypedExpr>): Void {
		final inner = stripWrap(e);
		switch(inner.expr) {
			case TBinop(OpOr, l, r):
				collectOrTerms(l, out);
				collectOrTerms(r, out);
			case _:
				out.push(inner);
		}
	}

	function isSameExpr(a: TypedExpr, b: TypedExpr): Bool {
		if(a == null || b == null) return a == b;
		final sa = stripWrap(a);
		final sb = stripWrap(b);
		return switch[sa.expr, sb.expr] {
			case [TLocal(v1), TLocal(v2)]: v1.id == v2.id;
			case [TConst(c1), TConst(c2)]: Std.string(c1) == Std.string(c2);
			case [TField(s1, fa1), TField(s2, fa2)]:
				fieldName(fa1) == fieldName(fa2) && isSameExpr(s1, s2);
			case _: false;
		};
	}

	function extractByteRead(e: TypedExpr): Null<{buf: TypedExpr, base: TypedExpr, offset: Int}> {
		final inner = stripWrap(e);
		var bufExpr: Null<TypedExpr> = null;
		var idxExpr: Null<TypedExpr> = null;
		switch(inner.expr) {
			case TCall(fn, args) if(args.length == 1):
				switch(stripWrap(fn).expr) {
					case TField(subj, fa) if(fieldName(fa) == "get"):
						bufExpr = subj;
						idxExpr = args[0];
					case _:
				}
			case TArray(arr, idx):
				bufExpr = arr;
				idxExpr = idx;
			case _:
		}
		if(bufExpr == null || idxExpr == null) {
			return null;
		}
		final strippedIdx = stripWrap(idxExpr);
		switch(strippedIdx.expr) {
			case TBinop(OpAdd, l, r):
				switch[stripWrap(l).expr, stripWrap(r).expr] {
					case [_, TConst(TInt(k))]:
						return {buf: bufExpr, base: l, offset: k};
					case [TConst(TInt(k)), _]:
						return {buf: bufExpr, base: r, offset: k};
					case _:
				}
			case _:
				return {buf: bufExpr, base: idxExpr, offset: 0};
		}
		return null;
	}

	function tryMatchFromBeBytes(e: TypedExpr): Null<String> {
		final terms: Array<TypedExpr> = [];
		collectOrTerms(e, terms);
		if(terms.length != 2 && terms.length != 4 && terms.length != 8) {
			return null;
		}
		final n = terms.length;
		final extracted: Array<{buf: TypedExpr, base: TypedExpr, offset: Int, shift: Int}> = [];
		for(i in 0...n) {
			final term = terms[i];
			var readExpr: TypedExpr = term;
			var shift = 0;
			switch(term.expr) {
				case TBinop(OpShl, inner, s):
					readExpr = inner;
					switch(stripWrap(s).expr) {
						case TConst(TInt(sh)): shift = sh;
						case _: return null;
					}
				case _:
					shift = 0;
			}
			final expectedShift = (n - 1 - i) * 8;
			if(shift != expectedShift) {
				return null;
			}
			final read = extractByteRead(readExpr);
			if(read == null) {
				return null;
			}
			if(read.offset != i) {
				return null;
			}
			if(i > 0) {
				if(!isSameExpr(read.buf, extracted[0].buf) || !isSameExpr(read.base, extracted[0].base)) {
					return null;
				}
			}
			extracted.push({buf: read.buf, base: read.base, offset: read.offset, shift: shift});
		}

		final typeName = switch(n) {
			case 2: "u16";
			case 4: "u32";
			case 8: "u64";
			case _: return null;
		};

		final bufStr = expr(extracted[0].buf);
		final baseStr = expr(extracted[0].base);
		final elems = [];
		for(i in 0...n) {
			if(i == 0) {
				elems.push(bufStr + "[" + baseStr + "]");
			} else {
				elems.push(bufStr + "[" + baseStr + " + " + i + "]");
			}
		}
		return typeName + "::from_be_bytes([" + elems.join(", ") + "])";
	}

	function isStringCharCodeAt(fn: TypedExpr): Bool {
		return switch(fn.expr) {
			case TField(subj, FInstance(_, _, cf)) if(cf.get().name == "charCodeAt" && isString(stripCast(subj))): true;
			case _: false;
		};
	}

	function resolveExprType(e: TypedExpr): String {
		final inner = stripWrap(e);
		switch(inner.expr) {
			case TLocal(v):
				if(argTypes.exists(v.name)) return argTypes.get(v.name);
			case _:
		}
		return types.of(e.t);
	}

	function tryMatchByteExtract(e: TypedExpr): Null<String> {
		final inner = stripWrap(e);
		var target: TypedExpr = inner;
		var shift = 0;
		switch(inner.expr) {
			case TBinop(OpUShr | OpShr, t, s):
				target = t;
				switch(stripWrap(s).expr) {
					case TConst(TInt(sh)): shift = sh;
					case _: return null;
				}
			case _:
				shift = 0;
		}
		final strippedTarget = stripWrap(target);
		switch(strippedTarget.expr) {
			case TCall(fn, _) if(isStringCharCodeAt(fn)):
				return expr(target);
			case _:
		}
		final targetType = resolveExprType(target);
		final bitWidth = switch(targetType) {
			case "u16": 16;
			case "u32": 32;
			case "u64": 64;
			case "u8": 8;
			case _: 32;
		};
		if(bitWidth == 8) {
			return expr(target);
		}
		if((bitWidth - 8 - shift) % 8 != 0 || shift < 0 || shift > bitWidth - 8) {
			return null;
		}
		final byteIndex = Std.int((bitWidth - 8 - shift) / 8);
		return expr(target) + ".to_be_bytes()[" + byteIndex + "]";
	}

	function isPassByRef(t: Type): Bool {
		if(isNullType(t)) return false;
		return switch(Context.follow(t)) {
			case TAbstract(a, _) if(a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")): true;
			case TInst(c, _) if(c.get().name == "Array" || c.get().name == "Bytes" || (c.get().pack.join(".") == "haxe.io" && c.get().name == "Bytes") || c.get().name == "String"): true;
			case _: false;
		};
	}

	function isInterfaceType(t: Null<Type>): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TInst(c, _): c.get().isInterface;
			case _: false;
		};
	}

	function renderValueForType(expected: Null<Type>, actual: TypedExpr, rendered: String): String {
		if(expected == null || actual == null) return rendered;
		// Rust represents an interface value as an owned trait object. A
		// concrete implementor therefore enters an interface slot through
		// the one sanctioned Box::new construction; an expression already
		// typed as the interface is already boxed by its declaration site.
		if(isInterfaceType(expected) && !isInterfaceType(actual.t)) {
			return "Box::new(" + rendered + ")";
		}
		// Static methods and static function fields are emitted as callable
		// items/pointers, while every non-static function value is already a
		// Box at its declaration site. Adapt the former only when a ruled
		// boxed function slot receives it.
		if(isFunctionType(expected) && isFunctionType(actual.t) && !isBoxedFunctionExpr(actual)) {
			return "Box::new(" + rendered + ")";
		}
		return rendered;
	}

	function isBoxedFunctionExpr(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TFunction(_): true;
			case TLocal(_): true;
			case TCall(_, _): true;
			case TField(_, FInstance(_, _, cf)) if(isFunctionType(cf.get().type)): true;
			case TField(_, FStatic(_, _)): false;
			case _: false;
		};
	}

	function renderCallArgs(fnType: Null<Type>, args: Array<TypedExpr>, signedPositions: Null<Array<Int>> = null, paramOffset: Int = 0): String {
		final paramTypes = if(fnType != null) {
			switch(Context.follow(fnType)) {
				case TFun(pargs, _): [for(p in pargs) p.t];
				case _: [];
			};
		} else [];
		final rendered = [];
		for(i in 0...args.length) {
			final arg = args[i];
			final paramIndex = i + paramOffset;
			final pt = paramIndex < paramTypes.length ? paramTypes[paramIndex] : null;
			var argStr = renderValueForType(pt, arg, expr(arg));
			if(paramIndex < paramTypes.length) {
				if(isNullType(pt) && !isNullType(arg.t)) {
					if(argStr == "None") {
						// already None
					} else {
						final inner = switch(stripWrap(arg).expr) {
							case TConst(TString(s)): quoteString(s) + ".to_string()";
							case _: argStr;
						};
						argStr = "Some(" + inner + ")";
					}
				} else if(RustType.isTypeParam(pt)) {
					final borrowed = switch(stripWrap(arg).expr) {
						case TLocal(v): isBorrowedLocal(v);
						case _: false;
					};
					if(isStringType(arg.t)) {
						// A generic T is owned in its return position. A Haxe
						// String argument therefore specializes T as String,
						// even when the source expression itself is a borrowed
						// string parameter or a literal.
						argStr = "&(" + argStr + ").to_string()";
					} else if(!borrowed && !StringTools.startsWith(argStr, "&")) {
						argStr = "&(" + argStr + ")";
					}
				} else if(isPassByRef(pt)) {
					// The mutating faces are arrays and the writer and reader
					// fronts; every other borrowed parameter reads only.
					final isArray = switch(Context.follow(pt)) {
						case TInst(c, _): c.get().name == "Array";
						default: false;
					};
					// A compile-time data table is a static declared at file scope:
					// it borrows immutably even where the parameter
					// accepts mutation.
					final isTableArg = switch(stripWrap(arg).expr) {
						case TField(_, FStatic(_, tableField)): DataTableHelper.isDataTableField(tableField.get());
						case _: false;
					};
					final prefix = isArray && !isTableArg ? "&mut " : "&";
					if(!StringTools.startsWith(argStr, "&")) {
						argStr = prefix + argStr;
					}
				}
				// A collection length is usize in Rust while a Haxe Int
				// function parameter is u32 in business modules. The
				// declared function type is the call boundary, so narrow
				// exactly there (the same convention as buf.len() as u32); the
				// stored function type remains unchanged.
				if(isIntType(pt) && isUsizeExpr(arg)
					&& (signedPositions == null || signedPositions.indexOf(i) < 0)) {
					final targetType = types.of(pt, false);
					if(targetType == "u32" || targetType == "i32") {
						argStr = "(" + argStr + ") as " + targetType;
					}
				}
			}
			if(signedPositions != null && signedPositions.indexOf(i) >= 0) {
				argStr = "(" + argStr + ") as i32";
			}
			rendered.push(argStr);
		}
		return rendered.join(", ");
	}

	function isUsizeExpr(e: TypedExpr): Bool {
		if(e == null) return false;
		return switch(stripWrap(e).expr) {
			case TField(subj, fa) if(fieldName(fa) == "length" || fieldName(fa) == "get_length"): staticGuardOf(subj) == null && !isStringBuf(subj);
			case TBinop(OpAdd | OpSub | OpMult | OpDiv, l, r): isUsizeExpr(l) || isUsizeExpr(r);
			default: false;
		};
	}

	function isScalarType(t: Type): Bool {
		final followed = Context.follow(t);
		return switch(followed) {
			case TAbstract(a, _):
				final name = a.get().name;
				name == "Bool" || name == "Int" || name == "Float";
			case TInst(c, _):
				c.get().name == "String";
			case _: false;
		};
	}

	function scalarTypeKind(t: Type): String {
		final followed = Context.follow(t);
		return switch(followed) {
			case TAbstract(a, _): a.get().name;
			case TInst(c, _): c.get().name;
			case _: "Unknown";
		};
	}

	function recordAggregateType(t: Type): Void {
		switch(t) {
			case TInst(c, params):
				final cls = c.get();
				if(cls.name == "Array") {
					final key = "Array_" + formatTypeKey(params[0]);
					if(!state.testReachableTypes.exists(key)) {
						state.testReachableTypes.set(key, t);
						recordAggregateType(params[0]);
					}
				} else if(cls.name == "Bytes" || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) {
					if(!state.testReachableTypes.exists("Bytes")) {
						state.testReachableTypes.set("Bytes", t);
					}
				}
			case TAbstract(a, params) if(a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
				final key = "Array_" + formatTypeKey(params[0]);
				if(!state.testReachableTypes.exists(key)) {
					state.testReachableTypes.set(key, t);
					recordAggregateType(params[0]);
				}
			case TType(def, params):
				final d = def.get();
				final key = d.module + "." + d.name;
				if(!state.testReachableTypes.exists(key)) {
					state.testReachableTypes.set(key, t);
					switch(d.type) {
						case TAnonymous(anon):
							for(f in anon.get().fields) {
								recordAggregateType(f.type);
							}
						case _:
					}
				}
			case TEnum(e, params):
				final en = e.get();
				final key = en.module + "." + en.name;
				if(!state.testReachableTypes.exists(key)) {
					state.testReachableTypes.set(key, t);
				}
			case _:
		}
	}

	function formatTypeKey(t: Type): String {
		return switch(t) {
			case TAbstract(a, params):
				if(a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")) "Array_" + formatTypeKey(params[0])
				else a.get().name;
			case TInst(c, params):
				final cls = c.get();
				if(cls.name == "Array") "Array_" + formatTypeKey(params[0]);
				else if(cls.name == "Bytes" || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) "Bytes";
				else cls.module + "." + cls.name;
			case TType(def, params): def.get().module + "." + def.get().name;
			case TEnum(e, params): e.get().module + "." + e.get().name;
			case _: "Unknown";
		};
	}

	function aggregateAssertFuncName(t: Type): String {
		return switch(t) {
			case TInst(c, params) if(c.get().name == "Array"):
				"assert_equals_vec_" + typeSafeSnake(params[0]);
			case TAbstract(a, params) if(a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
				"assert_equals_vec_" + typeSafeSnake(params[0]);
			case TInst(c, _) if(c.get().name == "Bytes" || (c.get().pack.join(".") == "haxe.io" && c.get().name == "Bytes")):
				"assert_equals_bytes";
			case TType(def, _):
				"assert_equals_" + RustImports.toSnakeCase(def.get().name);
			case TEnum(e, _):
				"assert_equals_" + RustImports.toSnakeCase(e.get().name);
			case _: "assert_equals_unknown";
		};
	}

	function typeSafeSnake(t: Type): String {
		return switch(t) {
			case TAbstract(a, _):
				switch(a.get().name) {
					case "Int": "u32";
					case "Float": FloatPrecision.isF32() ? "f32" : "f64";
					case "Bool": "bool";
					case "String": "string";
					case _: RustImports.toSnakeCase(a.get().name);
				}
			case TInst(c, _):
				switch(c.get().name) {
					case "String": "string";
					case "Bytes": "bytes";
					case _: RustImports.toSnakeCase(c.get().name);
				}
			case TType(def, _): RustImports.toSnakeCase(def.get().name);
			case TEnum(e, _): RustImports.toSnakeCase(e.get().name);
			case _: "unknown";
		};
	}

	function renderOptArg(e: TypedExpr, kind: String): String {
		// Both sides must reach the helper as Option. A Null-typed
		// expression already lowers to Option; any other expression
		// renders the inner value and is wrapped into Some. The String
		// kind clones because the same local may be borrowed by the
		// actual argument of the same call.
		return switch(e.expr) {
			case TConst(TNull): kind == "String" ? "None::<String>" : "None::<u32>";
			case _ if(isNullType(e.t)): expr(e);
			case TConst(TString(s)) if(kind == "String"): "Some(" + quoteString(s) + ".to_string())";
			case TConst(TInt(i)) if(kind == "Int"): "Some(" + Std.string(i) + ")";
			case _: kind == "String" ? "Some(" + expr(e) + ".clone())" : "Some(" + expr(e) + ")";
		};
	}

	function arrayArgBorrow(e: TypedExpr): String {
		// A direct array access can be borrowed without the value-read
		// clone; the borrow consumers above do not need the copy.
		return switch(e.expr) {
			case TArray(arr, idx): expr(arr) + "[(" + expr(idx) + ") as usize]";
			case _: expr(e);
		};
	}

	function isNullType(t: Type): Bool {
		if(t == null) return false;
		return switch(t) {
			case TAbstract(a, _): a.get().name == "Null";
			case _: false;
		};
	}

	function getNullInnerType(t: Type): Type {
		return switch(t) {
			case TAbstract(a, params) if(a.get().name == "Null"): params[0];
			case _: t;
		};
	}

	function isFloatType(t: Type): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Float";
			case _: false;
		};
	}

	function isIntType(t: Type): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Int";
			case _: false;
		};
	}

	/** Whether a division reads a length and divides by an Int, the
		shape the OpDiv lowering renders as truncating integer
		division; a general Int/Int division lowers through the module
		real (f64 by default, f32 under the precision switch). */
	function isLengthDivision(e: TypedExpr): Bool {
		return switch(e.expr) {
			case TBinop(OpDiv, l, r): isIntType(r.t) && StringTools.endsWith(operand(l, OpDiv, false), ".len()");
			case _: false;
		};
	}

	/** The parameter positions of one function type that carry Int. */
	function intParamPositions(fnType: Null<Type>): Null<Array<Int>> {
		if(fnType == null) return null;
		return switch(Context.follow(fnType)) {
			case TFun(pargs, _):
				final positions: Array<Int> = [];
				for(i in 0...pargs.length) {
					if(isIntType(pargs[i].t)) {
						positions.push(i);
					}
				}
				positions;
			case _: null;
		};
	}

	/** Whether one function type returns Int. */
	function returnsInt(fnType: Null<Type>): Bool {
		if(fnType == null) return false;
		return switch(Context.follow(fnType)) {
			case TFun(_, ret): isIntType(ret);
			case _: false;
		};
	}

	function isStringBuf(e: TypedExpr): Bool {
		if(e == null) return false;
		return switch(Context.follow(e.t)) {
			case TInst(c, _):
				final cls = c.get();
				(cls.pack.join(".") == "std" && cls.name == "StringBuf") || (cls.pack.length == 0 && cls.name == "StringBuf");
			case _: false;
		};
	}

	function isTNull(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(TNull): true;
			default: false;
		};
	}

	/**
		One branch of a two-arm conditional. A string literal renders as
		&str while a sibling member call that returns an owned String
		renders as String; Rust rejects the mismatched pair as one
		expression, so the lone literal branch converts. Two literals stay
		&str on both arms, and a sibling that renders as a borrow keeps
		the literal as &str too.
	**/
	function conditionalBranchText(branch: TypedExpr, sibling: TypedExpr): String {
		final text = expr(branch);
		if(!isStringType(branch.t) || !isStringType(sibling.t)) {
			return text;
		}
		if(!isStringLiteral(branch) || isStringLiteral(sibling)) {
			return text;
		}
		final siblingText = expr(sibling);
		final ownedStringCall = StringTools.endsWith(siblingText, ".to_string()")
			|| StringTools.endsWith(siblingText, ".to_string()?")
			|| StringTools.endsWith(siblingText, ".to_string().unwrap()");
		return ownedStringCall ? text + ".to_string()" : text;
	}

	function matchGroupByBody(body: Array<TypedExpr>): Null<{prefix: Array<TypedExpr>, entryVar: TVar, entryInit: TypedExpr, builderSubj: TypedExpr, keyArg: TypedExpr, valArg: TypedExpr}> {
		if(body.length == 0) return null;
		final last = body[body.length - 1];
		final coreStmts: Null<Array<TypedExpr>> = switch(last.expr) {
			case TBlock(s) if(s.length == 4): s;
			default:
				if(body.length == 4) body else null;
		};
		if(coreStmts == null) return null;
		final prefix = if(coreStmts == body) [] else body.slice(0, body.length - 1);
		final entry = switch(coreStmts[0].expr) {
			case TVar(v, init) if(init != null): { v: v, init: init };
			default: return null;
		};
		final builderInfo = switch(coreStmts[1].expr) {
			case TVar(bucketV, init) if(init != null):
				switch(stripWrap(init).expr) {
					case TCall(fn, args) if(args.length == 1):
						switch(fn.expr) {
							case TField(subj, fa) if(fieldName(fa) == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
								{ bucketVar: bucketV, builderSubj: subj, keyArg: args[0] };
							default: return null;
						}
					default: return null;
				}
			default: return null;
		};
		if(builderInfo == null) return null;
		final pushInfo = switch(coreStmts[coreStmts.length - 1].expr) {
			case TCall(fn, args) if(args.length == 1):
				switch(fn.expr) {
					case TField(subj, fa) if(fieldName(fa) == "push"):
						switch(stripWrap(subj).expr) {
							case TLocal(v) if(v.id == builderInfo.bucketVar.id):
								{ valArg: args[0] };
							default: return null;
						}
					default: return null;
				}
			default: return null;
		};
		if(pushInfo == null) return null;
		return {
			prefix: prefix,
			entryVar: entry.v,
			entryInit: entry.init,
			builderSubj: builderInfo.builderSubj,
			keyArg: builderInfo.keyArg,
			valArg: pushInfo.valArg
		};
	}
}
#end
