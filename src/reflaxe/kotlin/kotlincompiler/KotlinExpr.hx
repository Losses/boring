package kotlincompiler;

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
	Statement and expression lowering from the Haxe typed AST to Kotlin.
**/
class KotlinExpr {
	final imports: KotlinImports;
	final types: KotlinType;
	final state: KotlinEmissionState;

	/** True while emitting a function whose return type is ReadOnlyArray. */
	var decodeBoundary: Bool = false;

	/** Enum-capture locals mapped to the payload expression they stand for. */
	final subst: Map<Int, String> = [];

	/** Catch variables of the region being lowered; features/06 catch-site lowering. */
	final catchVars: Map<Int, Bool> = [];

	/** Locals reassigned after their declaration; emitted with var. */
	final mutated: Map<Int, Bool> = [];

	/** Fill arrays returning as asList() when decodeBoundary holds. */
	final asListReturn: Map<Int, String> = [];

	/** Locals backed by the FPHelper high/low boundary object. */
	final fpInt64Halves: Map<Int, Bool> = [];

	/** Names used by parameters and locals; generated names avoid them. */
	final usedNames: Map<String, Bool> = [];

	final hiddenNames: Map<Int, String> = [];
	var hiddenCounter: Int = 0;
	/** Fresh names for the trailing-unit reads of stdlib/08 checks. */
	var stringBufTailCounter: Int = 0;

	/** Function context used to distinguish a sanctioned coalescing site. */
	var currentClass: Null<ClassType> = null;
	var currentField: Null<String> = null;
	var currentLocalName: Null<String> = null;

	public function new(imports: KotlinImports, types: KotlinType, state: KotlinEmissionState) {
		this.imports = imports;
		this.types = types;
		this.state = state;
	}

	public function reserveName(name: String): Void {
		usedNames.set(name, true);
	}

	/** Binds a local to a rendered name; pattern captures adopt the payload argument name this way. */
	public function bindLocalName(v: TVar, name: String): Void {
		subst.set(v.id, name);
	}

	/** The rendered name of a local, if a binding was recorded. */
	public function boundNameOf(v: TVar): Null<String> {
		return subst.get(v.id);
	}

	public function setDecodeBoundary(value: Bool): Void {
		decodeBoundary = value;
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

	public function rawArrayExpression(e: TypedExpr, wrapper: String): String {
		return switch(stripWrap(e).expr) {
			case TArrayDecl(elements): wrapper + "(" + [for(x in elements) expr(x)].join(", ") + ")";
			case _: rawExpression(e);
		};
	}

	function coalescingSiteFor(e: TypedExpr): Null<{parameter: String, defaultExpr: TypedExpr, valueExpr: TypedExpr}> {
		if(currentClass == null || currentField == null) return null;
		final site = DefaultArgExpander.coalescingSite(e);
		final value = currentLocalName != null
			? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, site == null ? "" : site.parameter)
			: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, site == null ? "" : site.parameter);
		if(site == null || value == null) {
			return null;
		}
		return site;
	}

	/** Renders a sanctioned default in Kotlin's native parameter context. */
	public function coalescingDefaultText(value: DefaultArgExpander.CoalescingDefaultValue, targetType: Type): String {
		return switch(value) {
			case CInt(v): Std.string(v);
			case CFloat(s): FloatPrecision.isF32() ? (s.indexOf(".") >= 0 ? s : s + ".0") + "f" : s;
			case CString(s): quoteString(s);
			case CBool(b): b ? "true" : "false";
			case CNull: "null";
			case CEmptyArray:
				final element = switch(Context.follow(DefaultArgExpander.withoutNull(targetType))) {
					case TInst(_, params) if(params.length > 0): types.of(params[0]);
					case TAbstract(a, params) if(a.get().name == "ReadOnlyArray" && params.length > 0): types.of(params[0]);
					case _: "Nothing";
				};
				"mutableListOf<" + element + ">()";
			case CEmptyMap: "mutableMapOf()";
			case CPositiveInfinity: FloatPrecision.isF32() ? "Float.POSITIVE_INFINITY" : "Double.POSITIVE_INFINITY";
			case CNegativeInfinity: FloatPrecision.isF32() ? "Float.NEGATIVE_INFINITY" : "Double.NEGATIVE_INFINITY";
			case CEnum(enumRef, enumField): types.of(Type.TEnum(enumRef, [])) + "." + enumField.name;
			case CParameterRead(name): name;
			case CFieldAccess(CParameterRead(staticPath), ""): coalescingStaticFieldText(staticPath);
			case CFieldAccess(receiver, fieldName): coalescingDefaultText(receiver, targetType) + "." + (fieldName == "length" ? "size" : fieldName);
			case CMethodCall(receiver, methodName, args):
				coalescingDefaultText(receiver, targetType) + "." + kotlinMethodName(methodName) + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CStaticCall(fullPath, args):
				fullPath + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CConditional(c, t, f):
				"if (" + coalescingDefaultText(c, targetType) + ") " + coalescingDefaultText(t, targetType) + " else " + coalescingDefaultText(f, targetType);
			case CBinaryOp(op, left, right):
				coalescingDefaultText(left, targetType) + " " + opStr(op) + " " + coalescingDefaultText(right, targetType);
		};
	}

	function coalescingStaticFieldText(path:String):String {
		final parts = path.split(".");
		if(parts.length < 2) return path;
		final fieldName = parts[parts.length - 1];
		final typePath = parts.slice(0, parts.length - 1).join(".");
		try {
			switch(Context.getType(typePath)) {
				case TInst(clsRef, _): return staticRef(clsRef.get(), fieldName);
				default:
			}
		} catch (_:Dynamic) {}
		return path;
	}

	static function kotlinMethodName(name:String):String {
		return switch (name) {
			case "toUpperCase": "uppercase";
			case "toLowerCase": "lowercase";
			default: name;
		};
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
			case OpShl: "shl";
			case OpShr: "shr";
			case OpXor: "xor";
			case OpAssign: "=";
			case _: "?";
		};
	}

	// ------------------------------------------------------------------
	// Function bodies
	// ------------------------------------------------------------------

	public function functionBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) {
			Context.error("function field has no body to lower", f.field.pos);
		}
		DefaultArgExpander.completeRootExpr(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
		// Fuse declaration-plus-assignment pairs before the mutation scan.
		// The typer lowers abstract-inline receiver bindings as `TVar(v,
		// null)` followed by an assignment; the fused initializer is the
		// declaration's own initialization, so the scan must not read it as
		// a reassignment.
		final fusedRoot = fuseWithin(f.expr);
		f.expr.expr = fusedRoot.expr;
		scanLocals(f.expr);
		return blockLines(statementsOf(f.expr), 1);
	}

	/** Body lowering for members declared on a value wrapper. */
	public function valueTypeFunctionBody(cls: ClassType, f: ClassFuncData, fieldName: String): Array<String> {
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null && ValueTypeSupport.operatorOf(valueType, f.field) != null) {
			if(f.args.length > 0) bindLocalName(f.args[0].tvar, fieldName);
			if(f.args.length > 1) bindLocalName(f.args[1].tvar, "other");
		} else if(ValueTypeSupport.hasReceiver(f.field) && f.args.length > 0) {
			bindLocalName(f.args[0].tvar, fieldName);
		}
		return functionBody(cls, f);
	}

	/** Drops the representation assignment from a validating wrapper init. */
	public function valueTypeConstructorBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) Context.error("value type constructor has no body to lower", f.field.pos);
		DefaultArgExpander.completeRootExpr(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
		for(a in f.args) reserveName(a.name);
		scanLocals(f.expr);
		final out:Array<String> = [];
		for(stmt in statementsOf(f.expr)) {
			if(ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt)) continue;
			for(line in stmtLines(stmt, 2)) out.push(line);
		}
		return out;
	}

	/**
		The constructor body's init-block lines and the fields it
		initializes (feature spec 27): every statement renders at
		init-block depth, except `this.f = f` where f is a constructor
		parameter, which the primary constructor already performs. An
		assignment to a field the constructor does not receive as a
		parameter is that field's initialization; its name joins
		`assigned` so the declaration drops its synthetic initializer. An
		assignment to a parameter field from any other expression stops
		the compilation.
	**/
	public function initBlockStatements(cls: ClassType, f: ClassFuncData): {lines: Array<String>, assigned: Array<String>} {
		if(f.expr == null) {
			return {lines: [], assigned: []};
		}
		for(a in f.args) {
			reserveName(a.name);
		}
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
		scanLocals(f.expr);
		final out: Array<String> = [];
		final assigned: Array<String> = [];
		for(s in statementsOf(f.expr)) {
			final info = ctorStmtInfo(s, f);
			if(info.render) {
				for(l in stmtLines(s, 2)) out.push(l);
			}
			if(info.initialized != null && assigned.indexOf(info.initialized) < 0) {
				assigned.push(info.initialized);
			}
		}
		return {lines: out, assigned: assigned};
	}

	/**
		Per-statement decision behind initBlockStatements: `render` says
		whether the statement reaches the init block, `initialized` names
		the field a non-parameter assignment initializes.
	**/
	function ctorStmtInfo(s: TypedExpr, f: ClassFuncData): {render: Bool, initialized: Null<String>} {
		switch(s.expr) {
			case TBinop(OpAssign, target, value):
				switch(target.expr) {
					case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
						final name = cf.get().name;
						if(Lambda.exists(f.args, a -> a.name == name)) {
							final coalescing = coalescingSiteFor(value);
							if(coalescing != null && coalescing.parameter == name) {
								return {render: false, initialized: null};
							}
							final fromParam = switch(value.expr) {
								case TLocal(v): v.name == name;
								case _: false;
							};
							if(!fromParam) {
								Context.error("constructor assigns " + name + " from another expression; assign the constructor parameter " + name + " directly", s.pos);
							}
							// The primary constructor performs this
							// initialization from its parameter.
							return {render: false, initialized: null};
						}
						return {render: true, initialized: name};
					case _:
				}
			case _:
		}
		return {render: true, initialized: null};
	}

	// ------------------------------------------------------------------
	// Statements
	// ------------------------------------------------------------------

	public function statementsOf(e: TypedExpr): Array<TypedExpr> {
		return switch(e.expr) {
			case TBlock(stmts): stmts;
			case _: [e];
		};
	}

	function stmtLines(e: TypedExpr, depth: Int): Array<String> {
		switch(e.expr) {
			case TVar(v, init) if(isTryRegion(init)):
				final parts = tryRegionParts(init);
				if(regionTailValue(statementsOf(parts.body)) == null) {
					return fail(init, "try region body has no value");
				}
				return tryLines(parts.body, parts.c, depth, 'val ${localName(v)} = ');
			case TVar(v, init) if(isStringBufToStringCall(init)):
				return stringBufToStringBindingLines(v, stripWrap(init), depth);
			case TVar(v, init) if(init != null):
				final kw = mutated.exists(v.id) ? "var" : "val";
				switch(stripWrap(init).expr) {
					case TLocal(origV) if(asListReturn.exists(origV.id)):
						asListReturn.set(v.id, asListReturn.get(origV.id));
					default:
				}
				final typeAnn = switch(stripWrap(init).expr) {
					case TConst(TNull): ": " + types.of(v.t);
					default: "";
				};
				final initText = switch(init.expr) {
					case TFunction(fn): functionLiteralNamed(v.name, fn);
					default: expr(init);
				};
				return [indent(depth) + '$kw ${localName(v)}$typeAnn = $initText'];
			case TVar(_, init) if(init == null):
				return fail(e, "declaration without initializer has no lowering");
			case TBlock(stmts):
				return blockLines(stmts, depth);
			case TIf(c, t, f):
				final out = [indent(depth) + "if (" + expr(c) + ") {"];
				for(l in blockLines(statementsOf(t), depth + 1)) out.push(l);
				if(f != null) {
					out.push(indent(depth) + "} else {");
					for(l in blockLines(statementsOf(f), depth + 1)) out.push(l);
				}
				out.push(indent(depth) + "}");
				return out;
			case TWhile(c, b, true):
				final out = [indent(depth) + "while (" + expr(c) + ") {"];
				for(l in blockLines(statementsOf(b), depth + 1)) out.push(l);
				out.push(indent(depth) + "}");
				return out;
			case TWhile(_, _, false):
				return fail(e, "do-while has no lowering in the subset");
			case TReturn(ret) if(ret != null && isTryRegion(ret)):
				final parts = tryRegionParts(ret);
				if(regionTailValue(statementsOf(parts.body)) == null) {
					return fail(ret, "try region body has no value");
				}
				return tryLines(parts.body, parts.c, depth, "return ");
			case TReturn(ret) if(ret == null):
				return [indent(depth) + "return"];
			case TReturn(ret) if(isStringBufToStringCall(ret)):
				return stringBufToStringReturnLines(stripWrap(ret), depth);
			case TReturn(ret) if(isVariantSwitch(ret)):
				return whenReturnLines(stripWrap(ret), depth);
			case TReturn(ret):
				final inner = stripWrap(ret);
				switch(inner.expr) {
					case TLocal(v) if(asListReturn.exists(v.id)):
						return [indent(depth) + "return " + localName(v) + "." + asListReturn.get(v.id)];
					case _:
						return [indent(depth) + "return " + expr(ret)];
				}
			case TThrow(x):
				return [indent(depth) + "throw " + throwExpr(x)];
			case TTry(body, catches) if(catches.length == 1):
				return tryLines(body, catches[0], depth, "");
			case TTry(_, _):
				return fail(e, "try region handles exactly one exception domain");
			case TBreak:
				return [indent(depth) + "break"];
			case TContinue:
				return [indent(depth) + "continue"];
			case TCall(fn, args) if(stringBufMutationParts(fn) != null):
				return stringBufMutationLines(fn, args, depth);
			case TMeta(_, inner):
				return stmtLines(inner, depth);
			case _:
				return [indent(depth) + expr(e)];
		}
	}

	function throwExpr(x: TypedExpr): String {
		final inner = stripWrap(x);
		switch(inner.expr) {
			case TNew(c, _, args) if(args.length == 1 && state.exceptionPayloads.exists(c.get().module)):
				return exceptionVariant(c.get(), args[0]);
			case _:
		}
		return expr(x);
	}

	/**
		stdlib/08 string-buffer checks (Kotlin): every checked operation
		reads the trailing UTF-16 unit, and the fault constructs the
		sealed UnpairedSurrogate variant of std.UStringException. A throw
		is an expression here, so the checked operations stay usable in
		expression position; statements take the flat form below.
	**/
	function stringBufMutationParts(fn: TypedExpr): Null<{name: String, subj: TypedExpr}> {
		return switch(fn.expr) {
			case TField(subj, FInstance(_, _, cf)) if(isStringBuf(subj)):
				final n = cf.get().name;
				n == "add" || n == "addChar" ? {name: n, subj: subj} : null;
			case _: null;
		};
	}

	function stringBufTailRead(subj: TypedExpr): String {
		return expr(subj) + ".lastOrNull()?.code ?: -1";
	}

	function isStringBufToStringCall(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TCall(fn, _):
				switch(fn.expr) {
					case TField(subj, FInstance(_, _, cf)): cf.get().name == "toString" && isStringBuf(subj);
					case _: false;
				}
			case _: false;
		};
	}

	function stringBufToStringSubject(call: TypedExpr): TypedExpr {
		return switch(call.expr) {
			case TCall(fn, _):
				switch(fn.expr) {
					case TField(subj, _): subj;
					case _: call;
				}
			case _: call;
		};
	}

	/** Flat check for binding and return positions: one bound tail read, then the fault. */
	function stringBufToStringCheckLines(subj: TypedExpr, depth: Int): Array<String> {
		final tail = freshTailName();
		final lines = [indent(depth) + "val " + tail + " = " + stringBufTailRead(subj)];
		lines.push(indent(depth) + "if (" + stringBufLeadCond(tail) + ") {");
		lines.push(indent(depth + 1) + "throw " + stringBufFaultConstructor(tail));
		lines.push(indent(depth) + "}");
		return lines;
	}

	function stringBufToStringBindingLines(v: TVar, call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		final kw = mutated.exists(v.id) ? "var" : "val";
		lines.push(indent(depth) + kw + " " + localName(v) + " = " + expr(subj) + ".toString()");
		return lines;
	}

	function stringBufToStringReturnLines(call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		lines.push(indent(depth) + "return " + expr(subj) + ".toString()");
		return lines;
	}

	function stringBufLeadCond(x: String): String {
		return x + " >= 55296 && " + x + " <= 56319";
	}

	function stringBufTrailCond(x: String): String {
		return x + " >= 56320 && " + x + " <= 57343";
	}

	function stringBufAddFaultCond(subj: TypedExpr, partArg: TypedExpr): String {
		final part = expr(partArg);
		return stringBufLeadCond(stringBufTailRead(subj)) + " && " + part + ".length > 0"
			+ " && !(" + part + "[0].code >= 56320 && " + part + "[0].code <= 57343)";
	}

	function stringBufAddCharFaultCond(subj: TypedExpr, unitArg: TypedExpr): String {
		return "(" + stringBufTrailCond(expr(unitArg)) + ") != (" + stringBufLeadCond(stringBufTailRead(subj)) + ")";
	}

	function stringBufDanglingCond(subj: TypedExpr): String {
		return stringBufLeadCond(stringBufTailRead(subj));
	}

	function stringBufFaultConstructor(unit: String): String {
		imports.requireType("std.UStringException", "UStringException");
		return "UStringException.UnpairedSurrogate(" + unit + ")";
	}

	function freshTailName(): String {
		stringBufTailCounter += 1;
		return stringBufTailCounter == 1 ? "tail" : "tail" + stringBufTailCounter;
	}

	/** Statement lowering: one bound tail read, the check, then the op. */
	function stringBufMutationLines(fn: TypedExpr, args: Array<TypedExpr>, depth: Int): Array<String> {
		final parts = stringBufMutationParts(fn);
		if(parts == null) {
			return [fail(fn, "not a string buffer mutation")];
		}
		final buf = expr(parts.subj);
		final tail = freshTailName();
		final lines = [indent(depth) + "val " + tail + " = " + stringBufTailRead(parts.subj)];
		if(parts.name == "add") {
			final part = expr(args[0]);
			lines.push(indent(depth) + "if (" + stringBufLeadCond(tail) + " && " + part + ".length > 0"
				+ " && !(" + part + "[0].code >= 56320 && " + part + "[0].code <= 57343)) {");
			lines.push(indent(depth + 1) + "throw " + stringBufFaultConstructor(tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + ".append(" + part + ")");
		} else {
			final u = expr(args[0]);
			lines.push(indent(depth) + "if (" + stringBufTrailCond(u) + ") {");
			lines.push(indent(depth + 1) + "if (!(" + stringBufLeadCond(tail) + ")) {");
			lines.push(indent(depth + 2) + "throw " + stringBufFaultConstructor(u));
			lines.push(indent(depth + 1) + "}");
			lines.push(indent(depth) + "} else if (" + stringBufLeadCond(tail) + ") {");
			lines.push(indent(depth + 1) + "throw " + stringBufFaultConstructor(tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + ".append((" + u + ").toChar())");
		}
		return lines;
	}

	/** Renders `Owner.Variant` or `Owner.Variant(args)` for an exception construction over its payload enum. */
	function exceptionVariant(cls: ClassType, payloadArg: TypedExpr): String {		final owner = state.payloadEnumOwners.get(state.exceptionPayloads.get(cls.module));
		// The variant renders as a member of the exception class, so a
		// cross-package construction site needs the class import.
		imports.requireType(cls.module, cls.name);
		final arg = stripWrap(payloadArg);
		switch(arg.expr) {
			case TField(_, FEnum(_, ef)):
				return owner + "." + ef.name;
			case TCall(fn, callArgs):
				switch(stripWrap(fn).expr) {
					case TField(_, FEnum(_, ef)):
						return owner + "." + ef.name + "(" + [for(a in callArgs) expr(a)].join(", ") + ")";
					case _:
				}
			case _:
		}
		return owner + "(" + expr(payloadArg) + ")";
	}

	function fuseWithin(e: TypedExpr): TypedExpr {
		if(ValueTypeSupport.markedAbstractOfType(e.t) != null) {
			switch(e.expr) {
				case TBlock(_): return e;
				case _:
			}
		}
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

	function blockLines(stmts: Array<TypedExpr>, depth: Int): Array<String> {
		stmts = fuseUninitializedVars(stmts);
		stmts = regroupLoops(stmts);
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
		return out;
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
			case _:
				return null;
		}
	}

	function loopLines(loop, depth: Int): Array<String> {
		final name = loop.index.name;
		final startStr = expr(loop.start);
		final boundStr = loopBound(loop.bound);
		final out = [
			indent(depth) + "for (" + name + " in " + startStr + " until " + boundStr + ") {"
		];
		for(l in blockLines(loop.body, depth + 1)) out.push(l);
		out.push(indent(depth) + "}");
		return out;
	}

	function loopBound(bound: TypedExpr): String {
		final inner = stripWrap(bound);
		switch(inner.expr) {
			case TField(subj, fa) if(fieldName(fa) == "length"):
				final enumCollection = EnumQueryExpander.collectionEnum(subj);
				if(enumCollection != null) return Std.string(EnumQueryExpander.constructorCount(enumCollection));
				if(isString(subj)) {
					return expr(subj) + ".length";
				} else {
					return expr(subj) + ".size";
				}
			case _:
				return expr(bound);
		}
	}

	// ------------------------------------------------------------------
	// Counted fill (Array(count) { ... })
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

		final arrName = localName(alloc.arr);
		final boundStr = loopBound(loop.bound);
		final out: Array<String> = [];
		out.push(indent(depth) + "val " + arrName + " = Array(" + boundStr + ") { " + loop.index.name + " ->");
		final nonStores: Array<TypedExpr> = [];
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + expr(store.value));
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + expr(push.arg));
				continue;
			}
			nonStores.push(s);
		}
		if(nonStores.length > 0) {
			for(l in blockLines(nonStores, depth + 1)) out.push(l);
		}
		if(decodeBoundary) {
			out.push(indent(depth) + "}");
			asListReturn.set(alloc.arr.id, "asList()");
		} else {
			out.push(indent(depth) + "}.toMutableList()");
		}
		return out;
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
					case TInt(v): return Std.string(v);
					case TFloat(f):
						final s = Std.string(f);
						final padded = s.indexOf(".") >= 0 ? s : s + ".0";
						// The f32 configuration marks every literal so its width never
						// relies on the context's inference (feature spec 23).
						return FloatPrecision.isF32() ? padded + "f" : s;
					case TString(s): return quoteString(s);
					case TBool(b): return b ? "true" : "false";
					case TNull: return "null";
					case TThis: return "this";
					case TSuper: return "super";
					case _: return fail(e, "constant has no Kotlin lowering");
				}
			case TLocal(v):
				if(subst.exists(v.id)) {
					return subst.get(v.id);
				}
				return localName(v);
			case TArray(arr, idx):
				final mapReceiver = mapBackingReceiver(arr);
				return mapReceiver == null ? expr(arr) + "[" + expr(idx) + "]" : expr(mapReceiver) + "[" + expr(idx) + "]";
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
				final typeArg = switch(e.t) {
					case TInst(c, params) if(c.get().name == "Array" && params.length > 0):
						"<" + types.of(params[0]) + ">";
					case _: "";
				};
				return "mutableListOf" + typeArg + "(" + [for(x in elems) expr(x)].join(", ") + ")";
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
				// any `when` arm; the cast names the variant, and a
				// single-variant domain keeps the cast total.
				final en = switch(Context.follow(se.t)) {
					case TEnum(r, _): r.get();
					case _: return fail(e, "payload read subject is not a variant value");
				};
				if(Lambda.count(en.constructs) != 1) {
					return fail(e, "payload read of a multi-variant enum lowers inside a when arm only");
				}
				final owner = state.payloadEnumOwners.get(en.module);
				if(owner != null) {
					imports.requireType(en.pack.concat([owner]).join("."), owner);
					return "(" + expr(se) + " as " + owner + "." + ef.name + ")." + payloadName(ef, index);
				}
				imports.requireType(en.module, en.name);
				return "(" + expr(se) + " as " + en.name + "." + ef.name + ")." + payloadName(ef, index);
			case TEnumIndex(_):
				return fail(e, "enum index only lowers inside a variant switch");
			case TFunction(f):
				return functionLiteral(f);
			case TIf(c, t, f) if(f != null):
				final coalescing = coalescingSiteFor(e);
				if(coalescing != null) {
					if(currentLocalName != null && currentClass != null && currentField != null) {
						final value = DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, coalescing.parameter);
						if(value != null) return expr(coalescing.valueExpr) + " ?: " + coalescingDefaultText(value, coalescing.valueExpr.t);
					}
					return expr(coalescing.valueExpr);
				}
				return "(if (" + expr(c) + ") " + expr(t) + " else " + expr(f) + ")";
			case TSwitch(_, _, _):
				return switchExpression(e);
			case TTry(body, catches) if(catches.length == 1):
				return tryExpression(body, catches[0]);
			case TTry(_, _):
				return fail(e, "try region handles exactly one exception domain");
			case _:
				return fail(e, "expression has no Kotlin lowering in the subset: " + Std.string(e.expr));
		}
	}

	/** Lowers an abstract implementation block to a Kotlin value wrapper. */
	function valueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr):String {
		final abs = ValueTypeSupport.markedAbstractOfType(wrapper.t);
		if(abs == null) return expr(value);
		final locals = valueTypeLocalValues(wrapper);
		final activeAbs = currentClass == null ? null : ValueTypeSupport.markedAbstractOfClass(currentClass);
		final activeField = activeAbs != null && currentField != null ? ValueTypeSupport.memberField(activeAbs, currentField) : null;
		final nativeOperator = activeAbs != null && activeField != null && ValueTypeSupport.sameAbstract(activeAbs, abs)
			&& ValueTypeSupport.operatorOf(abs, activeField) != null;
		return switch(stripWrap(value).expr) {
			case TBinop(op, left, right):
				final field = ValueTypeSupport.binaryOperatorField(abs, op);
				if(field == null) expr(value) else {
					final asRepresentation = nativeOperator && field.name == currentField;
					final rendered = valueTypeOperand(left, locals, abs, asRepresentation) + " " + opStr(op) + " " + valueTypeOperand(right, locals, abs, asRepresentation);
					nativeOperator && field.name == currentField ? abs.name + "(" + rendered + ")" : rendered;
				}
			case TUnop(op, _, subject):
				final field = ValueTypeSupport.unaryOperatorField(abs, op);
				if(field == null) expr(value) else {
					final asRepresentation = nativeOperator && field.name == currentField;
					final rendered = "-" + valueTypeOperand(subject, locals, abs, asRepresentation);
					nativeOperator && field.name == currentField ? abs.name + "(" + rendered + ")" : rendered;
				}
			case _: abs.name + "(" + expr(value) + ")";
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
		final fieldName = abs == null ? "" : ValueTypeSupport.representationFieldName(abs);
		final alreadyRepresentation = switch(stripWrap(value).expr) {
			case TLocal(v) if(subst.exists(v.id) && subst.get(v.id) == fieldName): true;
			case _: false;
		};
		return asRepresentation && wrapperOperand && !alreadyRepresentation ? rendered + "." + fieldName : rendered;
	}

	function enumQuery(e:TypedExpr):Null<String> {
		switch(e.expr) {
			case TField(subj, fa):
				final name = switch(fa) { case FInstance(_, _, cf) | FAnon(cf): cf.get().name; case FDynamic(n): n; case _: ""; };
				final en = EnumQueryExpander.collectionEnum(subj); if(name == "length" && en != null) return Std.string(EnumQueryExpander.constructorCount(en));
			case TArray(subj, index): final en = EnumQueryExpander.collectionEnum(subj); if(en != null) { if(EnumQueryExpander.aliasEnum(subj) != null) return expr(subj) + "[" + expr(index) + "]"; imports.requireType(en.module, en.name); return en.name + ".entries[" + expr(index) + "]"; }
			case _:
		}
		final kind = EnumQueryExpander.markerKind(e); if(kind == null) return null;
		final en = EnumQueryExpander.enumOf(e); final args = EnumQueryExpander.callArgs(e); imports.requireType(en.module, en.name);
		return switch(kind) { case QCollection: en.name + ".entries"; case QName: expr(args[0]) + ".name"; case QLookup: en.name + ".entries.firstOrNull { it.name == " + expr(args[1]) + " }"; };
	}

	function functionLiteral(f: TFunc): String {
		final params = [for(a in f.args) '${a.v.name}: ${types.of(a.v.t)}'].join(", ");
		final ret = types.of(f.t);
		final retStr = ret == "Unit" ? "" : ": " + ret;
		return 'fun($params)$retStr {\n' + blockLines(statementsOf(f.expr), 1).join("\n") + '\n}';
	}

	// ------------------------------------------------------------------
	// Variant switches and try regions (features/01, features/06)
	// ------------------------------------------------------------------

	/**
		Renders an enum switch as a `when` expression. The typer hands the
		switch over with the subject wrapped in TEnumIndex and case values
		as construct-index constants; payload captures arrive as TEnumParameter
		initializations in the arm block and bind to property reads on the
		subject, which the `is` arm smart-casts to the variant type.
	**/
	function switchExpression(sw: TypedExpr): String {
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
		final owner = state.payloadEnumOwners.get(en.module);
		final receiver = owner != null ? owner : en.name;
		if(owner != null) {
			imports.requireType(en.pack.concat([owner]).join("."), owner);
		} else {
			imports.requireType(en.module, en.name);
		}
		final table = new Map<Int, EnumField>();
		for(name => ef in en.constructs) {
			table.set(ef.index, ef);
		}
		final out = ["when (" + subjStr + ") {"];
		for(c in parts.cases) {
			final index = switch(c.values[0].expr) {
				case TConst(TInt(v)): v;
				case _: return fail(sw, "variant switch case is not a constant index");
			}
			final ef = table.get(index);
			if(ef == null) {
				return fail(sw, "variant switch case index has no construct");
			}
			final arm = armLines(c.expr);
			// The `is` pattern smart-casts the subject to the variant, so
			// payload captures read as properties on it. Arms separate by
			// newline; Kotlin `when` takes no comma between arms.
			out.push("    " + (isValueEnum(en) ? "" : "is ") + receiver + "." + ef.name + " -> " + arm[0]);
			for(i in 1...arm.length) {
				out.push("    " + arm[i]);
			}
		}
		out.push("}");
		return out.join("\n");
	}

	static function isValueEnum(en: EnumType): Bool {
		for(ef in en.constructs) switch(Context.follow(ef.type)) {
			case TFun(args, _) if(args.length > 0): return false;
			case _:
		}
		return true;
	}

	/**
		Renders one switch arm. Payload captures fold into property reads on
		the subject; other declarations stay; the trailing statement is the
		arm value. A single-expression arm renders inline, anything longer
		renders as a block.
	**/
	function armLines(e: TypedExpr): Array<String> {
		final decls: Array<String> = [];
		var value: Null<String> = null;
		function walk(stmts: Array<TypedExpr>) {
			for(s in stmts) {
				switch(s.expr) {
					case TVar(v, init):
						if(init == null) {
							Context.error("kotlin target: declaration without initializer has no lowering", s.pos);
						}
						switch(stripWrap(init).expr) {
							case TEnumParameter(se, ef, index):
								subst.set(v.id, expr(se) + "." + payloadName(ef, index));
							case TLocal(source) if(subst.exists(source.id)):
								subst.set(v.id, subst.get(source.id));
							case _:
								decls.push("val " + localName(v) + " = " + expr(init));
						}
					case TBlock(bs):
						walk(bs);
					case TMeta(_, inner):
						walk([inner]);
					case _:
						value = expr(s);
				}
			}
		}
		walk(statementsOf(e));
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

	/**
		Renders a try region. Kotlin `try` is an expression, so statement and
		expression positions share one shape; the catch variable is typed with
		the exception class and registered so payload access on it lowers to
		the variable itself (features/06 catch-site lowering). `prefix`
		carries the binding or return the region produces its value for.
	**/
	function tryLines(body: TypedExpr, c: {v: TVar, expr: TypedExpr}, depth: Int, prefix: String): Array<String> {
		final varName = localName(c.v);
		final varType = types.of(c.v.t);
		final out = [indent(depth) + prefix + "try {"];
		for(l in blockLines(statementsOf(body), depth + 1)) {
			out.push(l);
		}
		out.push(indent(depth) + "} catch (" + varName + ": " + varType + ") {");
		catchVars.set(c.v.id, true);
		final handler = blockLines(statementsOf(c.expr), depth + 1);
		catchVars.remove(c.v.id);
		for(l in handler) {
			out.push(l);
		}
		out.push(indent(depth) + "}");
		return out;
	}

	function tryExpression(body: TypedExpr, c: {v: TVar, expr: TypedExpr}): String {
		return tryLines(body, c, 0, "").join("\n");
	}

	/** True when the expression is an enum switch over variant indices. */
	function isVariantSwitch(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TSwitch(_, _, _): true;
			case _: false;
		};
	}

	/** Return-position variant switch: the when value returns through the function edge. */
	function whenReturnLines(sw: TypedExpr, depth: Int): Array<String> {
		final lines = switchExpression(sw).split("\n");
		final out = [indent(depth) + "return " + lines[0]];
		for(i in 1...lines.length) {
			out.push(indent(depth) + lines[i]);
		}
		return out;
	}

	function isTryRegion(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TTry(_, catches): catches.length == 1;
			case _: false;
		};
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
				last;
		};
	}

	function tryRegionParts(e: TypedExpr): {body: TypedExpr, c: {v: TVar, expr: TypedExpr}} {
		return switch(stripWrap(e).expr) {
			case TTry(body, catches): {body: body, c: catches[0]};
			case _: {body: e, c: null};
		};
	}

	/**
		On a catch variable, the payload field of the exception class (the
		enum-typed field whose enum the region catches) reads as the variable
		itself: the folded tree makes the variable the variant value
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
												return localName(v);
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

	function binop(e: TypedExpr, op: Binop, l: TypedExpr, r: TypedExpr): String {
		switch(op) {
			case OpAssign:
				final map = mapAssignment(l);
				return map == null ? assignTarget(l) + " = " + expr(r) : expr(map.receiver) + ".put(" + expr(map.key) + ", " + expr(r) + ")";
			case OpAssignOp(inner):
				switch(inner) {
					case OpAdd | OpSub | OpMult | OpDiv | OpMod:
						return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
					case _:
						return assignTarget(l) + " = " + binopCore(inner, l, r);
				}
			case _:
				return binopCore(op, l, r);
		}
	}

	function isStringType(t: Type): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TInst(c, _): c.get().name == "String";
			case _: false;
		};
	}

	function binopCore(op: Binop, l: TypedExpr, r: TypedExpr): String {
		switch(op) {
			case OpAdd if(isStringType(l.t) || isStringType(r.t)):
				final leftStd = stdStringArg(l);
				final rightStd = stdStringArg(r);
				final leftText = leftStd == null ? operand(l, op, false) : stdString(leftStd, true);
				final rightText = rightStd == null ? operand(r, op, true) : stdString(rightStd, true);
				if(!isStringType(l.t)) {
					return "(" + leftText + ").toString() + " + rightText;
				}
				return leftText + " + " + rightText;
			case OpAdd | OpSub | OpMult | OpDiv | OpMod | OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte | OpBoolAnd | OpBoolOr:
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
			case OpShl:
				return "((" + operand(l, op, false) + ") shl (" + operand(r, op, true) + "))";
			case OpShr:
				return "((" + operand(l, op, false) + ") shr (" + operand(r, op, true) + "))";
			case OpUShr:
				return "((" + operand(l, op, false) + ") ushr (" + operand(r, op, true) + "))";
			case OpAnd:
				return "((" + operand(l, op, false) + ") and (" + operand(r, op, true) + "))";
			case OpOr:
				return "((" + operand(l, op, false) + ") or (" + operand(r, op, true) + "))";
			case OpXor:
				return "((" + operand(l, op, false) + ") xor (" + operand(r, op, true) + "))";
			case _:
				return fail(null, "unsupported binary operator: " + Std.string(op));
		}
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
			case OpNeg: return "-" + inner;
			case OpIncrement: return post ? inner + "++" : "++" + inner;
			case OpDecrement: return post ? inner + "--" : "--" + inner;
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
					case "make" if(args.length == 2): "((" + expr(args[0]) + ".toLong() shl 32) or (" + expr(args[1]) + ".toLong() and 0xFFFFFFFFL))";
					case "ofInt" if(args.length == 1): expr(args[0]) + ".toLong()";
					case "getHigh" | "get_high" if(args.length == 1): if(isFpHelperInt64Halves(args[0])) expr(args[0]) + ".high" else "(" + expr(args[0]) + " shr 32).toInt()";
					case "getLow" | "get_low" if(args.length == 1): if(isFpHelperInt64Halves(args[0])) expr(args[0]) + ".low" else expr(args[0]) + ".toInt()";
					case "add" if(args.length == 2): expr(args[0]) + " + " + expr(args[1]);
					case "sub" if(args.length == 2): expr(args[0]) + " - " + expr(args[1]);
					case "and" if(args.length == 2): "((" + expr(args[0]) + ") and (" + expr(args[1]) + "))";
					case "or" if(args.length == 2): "((" + expr(args[0]) + ") or (" + expr(args[1]) + "))";
					case "xor" if(args.length == 2): "((" + expr(args[0]) + ") xor (" + expr(args[1]) + "))";
					case "complement" if(args.length == 1): "(" + expr(args[0]) + ").inv()";
					case "shl" if(args.length == 2): "((" + expr(args[0]) + ") shl ((" + expr(args[1]) + ") and 63))";
					case "shr" if(args.length == 2): "((" + expr(args[0]) + ") shr ((" + expr(args[1]) + ") and 63))";
					case "ushr" if(args.length == 2): "((" + expr(args[0]) + ") ushr ((" + expr(args[1]) + ") and 63))";
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
				return staticRef(c.get(), cf.get().name);
			case FEnum(e, ef):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				if(owner != null) {
					imports.requireType(en.pack.concat([owner]).join("."), owner);
					return owner + "." + ef.name;
				}
				imports.requireType(en.module, en.name);
				return en.name + "." + ef.name;
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
							// The folded exception tree keeps the native
							// message property (features/06: display text).
							return localName(v) + ".message";
						case _:
					}
				}
				if(name == "length") {
					if(isString(subj)) {
						return expr(subj) + ".length";
					} else {
						return expr(subj) + ".size";
					}
				}
				return expr(subj) + "." + name;
			case FDynamic(name):
				if((name == "length" || name == "get_length") && isStringBuf(subj)) {
					return expr(subj) + ".length";
				}
				return fail(subj, "dynamic field access has no lowering");
			case FClosure(_):
				return fail(subj, "closure has no lowering");
		}
	}

	function staticRef(cls: ClassType, name: String): String {
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) {
			imports.requireType(valueType.module, valueType.name);
			return valueType.name + "." + name;
		}
		final markedField = findStaticField(cls, name);
		if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
			return imports.functionRef(cls.module, name, markedField.isPublic);
		}
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "String":
				return "String." + name;
			case "haxe.io.FPHelper":
				// The f32 configuration uses the two value-edge calls for
				// binary32; the 8-byte wire layout retains its f64 shape on
				// both configurations (feature spec 23).
				imports.requireType(cls.module, cls.name);
				if(FloatPrecision.isF32()) {
					if(name == "i64ToDouble") return "FPHelper.i64ToF32";
					if(name == "doubleToI64") return "FPHelper.f32ToI64";
				}
				return "FPHelper." + name;
			case "Math":
				// The f32 configuration reads every Math static from the Float family;
				// kotlin.math free functions carry Float overloads, so the
				// java.lang.Math (Double-only) reference is never emitted
				// under the switch (feature spec 23).
				if(FloatPrecision.isF32()) {
					if(name == "NaN") return "Float.NaN";
					if(name == "POSITIVE_INFINITY") return "Float.POSITIVE_INFINITY";
					if(name == "NEGATIVE_INFINITY") return "Float.NEGATIVE_INFINITY";
					return "kotlin.math." + name;
				}
				if(name == "NaN") return "Double.NaN";
				if(name == "POSITIVE_INFINITY") return "Double.POSITIVE_INFINITY";
				if(name == "NEGATIVE_INFINITY") return "Double.NEGATIVE_INFINITY";
				return "Math." + name;
			case "std.Test" | "std.__test_shim":
				final runtimePackage = RuntimeConfig.requireImportName("module std.Test");
				state.shimsUsed.set("std.Test", true);
				imports.require(runtimePackage + ".test.Test");
				return "Test." + name;
			case "std.SortedMap":
				// The sorted resident owns the factory functions; the
				// extern's `builder` maps onto the map flavor.
				imports.requireType("std.SortedMap", "SortedTable");
				return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
			case "std.SortedSet":
				imports.requireType("std.SortedSet", "SortedTable");
				return "SortedTable." + (name == "builder" ? "setBuilder" : name);
			case "std.UStringRT":
				final runtimePackage = RuntimeConfig.requireImportName("module std.UStringRT");
				state.shimsUsed.set("std.UStringRT", true);
				imports.require(runtimePackage + ".UString");
				return "UString." + name;
			case "std.Graphemes":
				final graphemesPackage = RuntimeConfig.requireImportName("module std.Graphemes");
				state.shimsUsed.set("std.Graphemes", true);
				imports.require(graphemesPackage + ".Graphemes");
				return "Graphemes." + name;
			case _:
				if(cls.module == "std.Test") {
					final runtimePackage = RuntimeConfig.requireImportName("module std.Test");
					state.shimsUsed.set("std.Test", true);
					imports.require(runtimePackage + ".test.Test");
					return "Test." + name;
				}
				if(cls.module == "std.SortedMap") {
					imports.requireType("std.SortedMap", "SortedTable");
					return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
				}
				if(cls.module == "std.SortedSet") {
					imports.requireType("std.SortedSet", "SortedTable");
					return "SortedTable." + (name == "builder" ? "setBuilder" : name);
				}
				if(cls.module == "std.UStringRT") {
					final runtimePackage = RuntimeConfig.requireImportName("module std.UStringRT");
					state.shimsUsed.set("std.UStringRT", true);
					imports.require(runtimePackage + ".UString");
					return "UString." + name;
				}
				if(cls.module == "std.Graphemes") {
					final graphemesPackage = RuntimeConfig.requireImportName("module std.Graphemes");
					state.shimsUsed.set("std.Graphemes", true);
					imports.require(graphemesPackage + ".Graphemes");
					return "Graphemes." + name;
				}
				imports.requireType(cls.module, cls.name);
				return cls.name + "." + name;
		}
	}

	function findStaticField(cls: ClassType, name: String): Null<ClassField> {
		for(field in cls.statics.get()) {
			if(field.name == name) return field;
		}
		return null;
	}

	function typeExpr(t: ModuleType): String {
		switch(t) {
			case TClassDecl(c):
				final cls = c.get();
				if(cls.pack.length == 0 && (cls.name == "String" || cls.name == "Math")) {
					return cls.name;
				}
				if(cls.module == "std.Test" || (cls.pack.join(".") == "std" && (cls.name == "Test" || cls.name == "__test_shim"))) {
					final runtimePackage = RuntimeConfig.requireImportName("module std.Test");
					state.shimsUsed.set("std.Test", true);
					imports.require(runtimePackage + ".test.Test");
					return "Test";
				}
				imports.requireType(cls.module, cls.name);
				return cls.name;
			case TEnumDecl(e):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				if(owner != null) {
					return owner;
				}
				imports.requireType(en.module, en.name);
				return en.name;
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
		return known != null ? (known ? "true" : "false") : expr(args[0]) + " is " + expr(args[1]);
	}

	function stdStringType(t: Type, value: String, inConcat: Bool, origin: TypedExpr, depth: Int = 0): String {
		return switch(Context.follow(t)) {
			case TInst(c, _) if(c.get().name == "String"): value;
			case TInst(c, [element]) if(c.get().name == "Array"):
				final index = depth == 0 ? "i" : "i" + depth;
				final item = stdStringType(element, value + "[" + index + "]", true, origin, depth + 1);
				'run { val sb = StringBuilder(); sb.append(\'[\'); val n = ${value}.size; var ${index} = 0; while (${index} < n) { if (${index} > 0) { sb.append(", "); }; sb.append(${item}); ${index} += 1; }; sb.append(\']\'); sb.toString() }';
			case TInst(c, _) if(StaticFieldHelper.hasSelfConstructionStatic(c.get()) || c.get().meta.has(":dataClass")): value + ".toString()";
			case TAbstract(a, _) if(ValueTypeSupport.isMarkedAbstract(a.get())):
				final abs = a.get();
				if(ValueTypeSupport.memberField(abs, "toString") != null) {
					value + ".toString()";
				} else {
					final representation = value + "." + ValueTypeSupport.representationFieldName(abs);
					inConcat ? representation : "(" + representation + ").toString()";
				}
			case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool"): inConcat ? value : "(" + value + ").toString()";
			case TAbstract(a, params) if(a.get().module == "std.ReadOnlyArray"):
				stdStringType(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, inConcat, origin, depth);
			case TEnum(en, _) if(isParameterlessEnum(en.get())): value + (inConcat ? "" : ".name");
			case TEnum(_, _): inConcat ? value : value + ".toString()";
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
		final digits = args.length > 1 && !isNullExpr(args[1]) ? args[1] : null;
		if(isNegativeIntLiteral(value) || (digits != null && isNegativeIntLiteral(digits))) {
			Context.error("StringTools.hex accepts non-negative arguments only", value.pos);
		}
		final valueText = "(" + expr(value) + ")";
		final hex = valueText + ".toString(16).uppercase()";
		return digits == null ? hex : hex + ".padStart(" + expr(digits) + ", '0')";
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

	function isNullExpr(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(TNull): true;
			case _: false;
		};
	}

	/** Routes calls on a marked abstract implementation to value members. */
	function valueTypeCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
		switch(stripWrap(fn).expr) {
			case TField(_, FStatic(c, cf)):
				final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
				if(abs == null) return null;
				final field = cf.get();
				if(field.name == "_new") return args.length == 0 ? abs.name : abs.name + "(" + expr(args[0]) + ")";
				final op = ValueTypeSupport.operatorOf(abs, field);
				if(op != null) {
					return switch(op) {
						case Binary(_): args.length >= 2 ? expr(args[0]) + " " + opStrForValue(op) + " " + expr(args[1]) : abs.name;
						case Unary(_): args.length > 0 ? "-" + expr(args[0]) : abs.name;
					};
				}
				if(ValueTypeSupport.hasReceiver(field) && args.length > 0) {
					final tail = [for(i in 1...args.length) expr(args[i])].join(", ");
					return expr(args[0]) + "." + kotlinMethodName(field.name) + "(" + tail + ")";
				}
				return abs.name + "." + field.name + "(" + [for(a in args) expr(a)].join(", ") + ")";
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
				if(abs == null) return null;
				return expr(subj) + "." + kotlinMethodName(cf.get().name) + "(" + [for(a in args) expr(a)].join(", ") + ")";
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
						// Property getter on a caught exception: the native
						// message property (features/06: display text).
						return localName(v) + ".message";
					case _:
				}
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final name = cf.get().name;
				if(cls.pack.length == 0 && cls.name == "StringTools" && name == "hex") {
					return stringToolsHex(args);
				}
				if(cls.pack.length == 0 && cls.name == "StringTools" && name == "trim" && args.length == 1) {
					return expr(args[0]) + ".trim()";
				}
				if(cls.module == "Math" && name == "isNaN") return "(" + expr(args[0]) + ").isNaN()";
				if(cls.module == "Math" && name == "isFinite") return "(" + expr(args[0]) + ").isFinite()";
				if(cls.module == "Std" && (name == "parseFloat" || name == "parseInt") && args.length == 1) {
					final s = expr(args[0]);
					final real = FloatPrecision.isF32() ? "Float" : "Double";
					final nan = FloatPrecision.isF32() ? "Float.NaN" : "Double.NaN";
					if(name == "parseFloat") return "run { val s = " + s + "; val t = s.trim(' ', '\\t', '\\n', '\\r', '\\u000B', '\\u000C'); var i = 0; if (i < t.length && (t[i] == '+' || t[i] == '-')) i++; val before = i; while (i < t.length && t[i] in '0'..'9') i++; val hasBefore = i > before; var hasAfter = false; if (i < t.length && t[i] == '.') { i++; val start = i; while (i < t.length && t[i] in '0'..'9') i++; hasAfter = i > start } else if (!hasBefore) return@run " + nan + "; if (!hasBefore && !hasAfter) return@run " + nan + "; if (i < t.length && (t[i] == 'e' || t[i] == 'E')) { i++; if (i < t.length && (t[i] == '+' || t[i] == '-')) i++; val start = i; while (i < t.length && t[i] in '0'..'9') i++; if (i == start) return@run " + nan + " }; if (i != t.length) " + nan + " else t." + (FloatPrecision.isF32() ? "toFloatOrNull() ?: Float.NaN" : "toDoubleOrNull() ?: Double.NaN") + " }";
					return "run { val s = " + s + "; val t = s.trim(' ', '\\t', '\\n', '\\r', '\\u000B', '\\u000C'); val neg = t.startsWith(\"-\"); val sign = if (neg || t.startsWith(\"+\")) 1 else 0; val hex = t.startsWith(\"0x\", sign) || t.startsWith(\"0X\", sign); val d = if (hex) t.substring(sign + 2) else t.substring(sign); if (!hex) { var i = sign; val start = i; while (i < t.length && t[i] in '0'..'9') i++; if (i != t.length || i == start) null else t.toIntOrNull() } else { var i = 0; while (i < d.length && d[i] in '0'..'9' || i < d.length && d[i] in 'a'..'f' || i < d.length && d[i] in 'A'..'F') i++; if (i != d.length || d.isEmpty()) null else { val n = d.toLongOrNull(16); if (n == null) null else { val v = if (neg) -n else n; if (v >= -2147483648L && v <= 2147483647L) v.toInt() else null } } } }";
				}
				final markedField = findStaticField(cls, name);
				if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
					final nativeName = staticRef(cls, name);
					final rendered = [for(a in args) expr(a)];
					if(StaticFunctionMarkers.isExtension(markedField)) {
						return expr(args[0]) + "." + nativeName + "(" + rendered.slice(1).join(", ") + ")";
					}
					return nativeName + "(" + rendered.join(", ") + ")";
				}
				if(cls.module == "std.UStringPlatform") {
					// Cursor primitives of the resident UString walk, inlined
					// per call: a cursor is a UTF-16 unit index here, so end
					// is the unit length and codePointAt combines surrogate
					// pairs. Business code never reaches these; it calls
					// std.UString.
					switch(name) {
						case "end":
							return expr(args[0]) + ".length";
						case "codeAt":
							return expr(args[0]) + ".codePointAt(" + expr(args[1]) + ")";
						case "advance":
							return "(" + expr(args[1]) + " + Character.charCount(" + expr(args[0]) + ".codePointAt(" + expr(args[1]) + ")))";
						case "substringBetween":
							return expr(args[0]) + ".substring(" + expr(args[1]) + ", " + expr(args[2]) + ")";
						case "fromCodePoint":
							return "String(Character.toChars(" + expr(args[0]) + "))";
						case _:
					}
				}
				if(cls.module == "std.TestPlatform") {
					// Host edges of the resident runtime.TestCore, inlined
					// per call: raising is an AssertionError, the running
					// test id lives in the Test host of this same package,
					// and plain numbers render through toString. Marking the
					// std.Test shim used keeps that host emitted beside this
					// resident. Business code never reaches these; it calls
					// std.Test.
					if(!imports.selfResident) {
						Context.error("std.TestPlatform is a resident runtime primitive; business code calls std.Test", fn.pos);
					}
					state.shimsUsed.set("std.Test", true);
					switch(name) {
						case "raise":
							return "throw AssertionError(" + expr(args[0]) + ")";
						case "currentTestId":
							return "Test.currentTestIdState()";
						case "intToString":
							return "(" + expr(args[0]) + ").toString()";
						case "floatToString":
							return "(" + expr(args[0]) + ").toString()";
						case _:
					}
				}
				if((cls.name == "Functional" || cls.name == "__functional_shim" || cls.module == "std.Functional" || cls.pack.join(".") + "." + cls.name == "std.Functional") && name == "sortedBy") {
					final receiver = args[0];
					final lambda = args[1];
					final func = unwrapLambda(lambda);
					if(func != null && func.args.length == 1) {
						final paramName = func.args[0].v.name;
						final keyExpr = expr(lambdaBody(func.expr));
						return expr(receiver) + ".toMutableList().apply { sortBy { " + paramName + " -> " + keyExpr + " } }";
					}
				}
			case _:
		}
		final inlineMapCall = mapHasOwnPropertyCall(fn, args);
		if(inlineMapCall != null) {
			return inlineMapCall;
		}
		final renderedArgs = localCallArgs(fn, args);
		switch(fn.expr) {
			case TCast(inner, _):
				return call(inner, args);
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return expr(subj) + ".length";
			case TField(subj, FInstance(_, _, cf)):
				final name = cf.get().name;
				if(isString(subj)) {
					if(name == "toLowerCase") return expr(subj) + ".lowercase()";
					if(name == "toUpperCase") return expr(subj) + ".uppercase()";
				}
				if(isMapType(subj.t)) {
					if(name == "exists" && args.length == 1) return expr(subj) + ".containsKey(" + expr(args[0]) + ")";
					if(name == "get" && args.length == 1) return expr(subj) + "[" + expr(args[0]) + "]";
					if(name == "set" && args.length == 2) return expr(subj) + ".put(" + expr(args[0]) + ", " + expr(args[1]) + ")";
				}
				if(isStringBuf(subj)) {
					// stdlib/08: a Kotlin throw is an expression, so the
					// checked operations stay expression-capable; the
					// statement form below emits the flat check + op pair.
					if(name == "add") {
						return "if (" + stringBufAddFaultCond(subj, args[0]) + ") throw " + stringBufFaultConstructor(stringBufTailRead(subj))
							+ " else " + expr(subj) + ".append(" + expr(args[0]) + ")";
					}
					if(name == "addChar") {
						final u = expr(args[0]);
						final unit = "if (" + stringBufTrailCond(u) + ") " + u + " else " + stringBufTailRead(subj);
						return "if (" + stringBufAddCharFaultCond(subj, args[0]) + ") throw " + stringBufFaultConstructor(unit)
							+ " else " + expr(subj) + ".append((" + u + ").toChar())";
					}
					if(name == "toString") {
						return "if (" + stringBufDanglingCond(subj) + ") throw " + stringBufFaultConstructor(stringBufTailRead(subj))
							+ " else " + expr(subj) + ".toString()";
					}
					if(name == "get_length" || name == "length") {
						return expr(subj) + ".length";
					}
				}
				if(name == "get" && isBytes(stripCast(subj))) {
					return "(( " + expr(subj) + "[" + expr(args[0]) + "].toInt() and 0xFF ))";
				}
				if(name == "charCodeAt" && isString(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + "].code";
				}
				if(name == "substring" && isString(stripCast(subj))) {
					// The haxe typer passes a synthesized null for an
					// omitted ?endIndex; the platform one-argument
					// overload is the suffix call, so the null argument
					// is omitted from the rendered call.
					final endOmitted = args.length < 2 || switch(stripWrap(args[1]).expr) {
						case TConst(TNull): true;
						case _: false;
					};
					if(endOmitted) {
						return expr(subj) + ".substring(" + expr(args[0]) + ")";
					}
				}
				if(name == "push") {
					return expr(subj) + ".add(" + renderedArgs + ")";
				}
				if(name == "join") {
					return expr(subj) + ".joinToString(" + renderedArgs + ")";
				}
				return expr(subj) + "." + name + "(" + renderedArgs + ")";
			case TField(_, FStatic(c, cf)):
				final cls = c.get();
				final name = cf.get().name;
				if(cls.pack.length == 0 && cls.name == "String" && name == "fromCharCode") {
					return "((" + expr(args[0]) + ").toChar()).toString()";
				}
				if(cls.pack.join(".") == "std" && cls.name == "Process" && name == "exit") {
					imports.require("kotlin.system.exitProcess");
				}
				if(cls.module == "std.Test" || (cls.pack.join(".") == "std" && (cls.name == "Test" || cls.name == "__test_shim"))) {
					if(name == "equals") {
						final expectedArg = args[0];
						final actualArg = args[1];
						final msgArg = args.length > 2 ? expr(args[2]) : null;
						if(isScalarType(expectedArg.t)) {
							final runtimePackage = RuntimeConfig.requireImportName("module std.Test");
							state.shimsUsed.set("std.Test", true);
							imports.require(runtimePackage + ".test.Test");
							return "Test.equals(" + expr(expectedArg) + ", " + expr(actualArg) + (msgArg != null ? ", " + msgArg : "") + ")";
						} else {
							recordAggregateType(expectedArg.t);
							imports.require("tests.TestHelper");
							return "TestHelper.assertEquals(" + expr(expectedArg) + ", " + expr(actualArg) + (msgArg != null ? ", " + msgArg : "") + ")";
						}
					}
				}
				if(cls.pack.length == 0 && cls.name == "Math" && name == "isNaN") {
					return "(" + expr(args[0]) + ").isNaN()";
				}
				if(cls.pack.length == 0 && cls.name == "Math" && name == "isFinite") {
					return "(" + expr(args[0]) + ").isFinite()";
				}
				if(cls.pack.length == 0 && cls.name == "Std" && name == "int") {
					// toInt on an Int expression is the identity; the
					// Kotlin compiler reports the call as redundant.
					// Haxe types Int/Int division as Float, but Kotlin
					// renders it as Int division, which already
					// truncates.
					if(isIntType(args[0].t)) {
						return expr(args[0]);
					}
					if(isIntDivision(args[0])) {
						return "(" + expr(args[0]) + ")";
					}
					return "(" + expr(args[0]) + ").toInt()";
				}
				if(cls.pack.join(".") == "std" && cls.name == "SortedMap" && name == "builder") {
					final kType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
						case _: null;
					};
					final vType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 1): params[1];
						case _: null;
					};
					return "SortedTable.mapBuilder<" + types.of(kType) + ", " + types.of(vType) + ">(" + sortedComparator("std.SortedMap", kType, fn.pos) + ")";
				}
				if(cls.pack.join(".") == "std" && cls.name == "SortedSet" && name == "builder") {
					final kType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
						case _: null;
					};
					return "SortedTable.setBuilder<" + types.of(kType) + ">(" + sortedComparator("std.SortedSet", kType, fn.pos) + ")";
				}
				return staticRef(cls, name) + "(" + renderedArgs + ")";
			case TField(subj, FEnum(e, ef)):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				if(owner != null) {
					return owner + "." + ef.name + "(" + renderedArgs + ")";
				}
				imports.requireType(en.module, en.name);
				return isValueEnum(en) ? en.name + "." + ef.name : en.name + "." + ef.name + "(" + renderedArgs + ")";
			case TConst(TSuper):
				return "super(" + renderedArgs + ")";
			case _:
				return expr(fn) + "(" + renderedArgs + ")";
		}
	}

	function localCallArgs(fn: TypedExpr, args: Array<TypedExpr>): String {
		final rendered = [for(a in args) expr(a)];
		switch(fn.expr) {
			case TLocal(v) if(currentClass != null && currentField != null):
				final params = switch(Context.follow(fn.t)) {
					case TFun(values, _): values;
					case _: [];
				};
				for(i in args.length...params.length) {
					if(DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, v.name, params[i].name) != null) {
						rendered.push("null");
					}
				}
			default:
		}
		return rendered.join(", ");
	}

	function functionLiteralNamed(name: String, f: TFunc): String {
		final previous = currentLocalName;
		currentLocalName = name;
		final result = functionLiteral(f);
		currentLocalName = previous;
		return result;
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) return args.length == 0 ? valueType.name : valueType.name + "(" + expr(args[0]) + ")";
		final renderedArgs = [for(a in args) expr(a)].join(", ");
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return "StringBuilder()";
			case "haxe.ds._Map.Map_Impl_":
				return "mutableMapOf()";
			case "haxe.io.BytesBuffer":
				imports.requireType(path, "BytesBuffer");
				return "BytesBuffer(" + renderedArgs + ")";
			case "Array":
				imports.require("java.util.ArrayList");
				return "ArrayList<" + types.of(params[0]) + ">(" + renderedArgs + ")";
			case _:
				if(args.length == 1 && state.exceptionPayloads.exists(cls.module)) {
					return exceptionVariant(cls, args[0]);
				}
				imports.requireType(cls.module, cls.name);
				return cls.name + "(" + renderedArgs + ")";
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
				receiver == null ? null : expr(receiver) + ".containsKey(" + expr(args[1]) + ")";
			case _: null;
		};
	}

	function assignTarget(e: TypedExpr): String {
		switch(e.expr) {
			case TArray(arr, idx):
				return expr(arr) + "[" + expr(idx) + "]";
			case TField(_, FStatic(c, cf)):
				return staticRef(c.get(), cf.get().name);
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				return expr(subj) + "." + cf.get().name;
			case TLocal(v):
				return localName(v);
			case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
				return assignTarget(inner);
			case _:
				return fail(e, "assignment target has no Kotlin lowering: " + Std.string(e.expr));
		}
	}

	function objectLiteral(e: TypedExpr, fields: Array<{name: String, expr: TypedExpr}>): String {
		final typeName = resolveTypeName(e.t);
		final parts = [for(f in fields) f.name + " = " + expr(f.expr)];
		return typeName + "(" + parts.join(", ") + ")";
	}

	function resolveTypeName(t: Type): String {
		return switch(t) {
			case TType(def, _):
				final d = def.get();
				imports.requireType(d.module, d.name);
				d.name;
			case TAnonymous(anon):
				final match = state.structTypedefs.get(KotlinDecl.structureSignature(anon));
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
					switch(stripWrap(init).expr) {
						case TCall(fn, _) if(isFpHelperInt64Call(fn)): fpInt64Halves.set(v.id, true);
						case _:
					}
				}
			case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
				switch(t.expr) {
					case TLocal(v): mutated.set(v.id, true);
					case _:
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
			case _: fail(null, "operator symbol has no Kotlin lowering: " + Std.string(op));
		}
	}

	function precedenceOf(op: Binop): Int {
		return switch(op) {
			case OpBoolOr: 1;
			case OpBoolAnd: 2;
			case OpOr | OpXor | OpAnd: 3;
			case OpEq | OpNotEq: 4;
			case OpLt | OpLte | OpGt | OpGte: 5;
			case OpShl | OpShr | OpUShr: 6;
			case OpAdd | OpSub: 7;
			case OpMult | OpDiv | OpMod: 8;
			case _: 0;
		}
	}

	function associative(op: Binop): Bool {
		return switch(op) {
			case OpBoolAnd | OpBoolOr | OpAdd | OpMult: true;
			case _: false;
		}
	}

	function fieldName(fa: FieldAccess): String {
		return switch(fa) {
			case FInstance(_, _, cf): cf.get().name;
			case FStatic(_, cf): cf.get().name;
			case FAnon(cf): cf.get().name;
			case FDynamic(n): n;
			case FClosure(_, cf): cf.get().name;
			case FEnum(_, ef): ef.name;
		}
	}

	/** The declared argument name of an enum constructor's payload. */
	public function payloadName(ef: EnumField, index: Int): String {
		return switch(ef.type) {
			case TFun(args, _) if(index < args.length): args[index].name;
			case _: "v" + index;
		}
	}

	function isBytes(e: TypedExpr): Bool {
		return switch(e.t) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
			case _: false;
		}
	}

	function isString(e: TypedExpr): Bool {
		return switch(e.t) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "" && cls.name == "String";
			case _: false;
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
			case TCast(inner, _): stripCast(inner);
			case _: e;
		}
	}

	function stripWrap(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripWrap(inner);
			case _: e;
		}
	}

	function quoteString(s: String): String {
		final b = new StringBuf();
		b.addChar('"'.code);
		for(i in 0...s.length) {
			switch(s.charCodeAt(i)) {
				case 34: b.add('\\"');
				case 92: b.add('\\\\');
				case 10: b.add('\\n');
				case 13: b.add('\\r');
				case 9: b.add('\\t');
				case 36: b.add('\\$');
				case c: b.addChar(c);
			}
		}
		b.addChar('"'.code);
		return b.toString();
	}

	function indent(depth: Int): String {
		final b = new StringBuf();
		for(i in 0...depth) {
			b.add("    ");
		}
		return b.toString();
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

	function isIntType(t: Null<Type>): Bool {
		if(t == null) return false;
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Int";
			case _: false;
		};
	}

	/** Whether both operands of a division carry Int, so Kotlin
		renders it as truncating Int division. */
	function isIntDivision(e: TypedExpr): Bool {
		return switch(e.expr) {
			case TBinop(OpDiv, l, r): isIntType(l.t) && isIntType(r.t);
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

	function recordAggregateType(t: Type): Void {
		switch(t) {
			case TInst(c, params) if(c.get().name == "Array"):
				final key = "Array_" + formatTypeKey(params[0]);
				if(!state.testReachableTypes.exists(key)) {
					state.testReachableTypes.set(key, t);
					recordAggregateType(params[0]);
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
				final owner = state.payloadEnumOwners.get(en.module);
				final typeName = owner != null ? en.pack.concat([owner]).join(".") : en.module + "." + en.name;
				final key = typeName;
				if(!state.testReachableTypes.exists(key)) {
					state.testReachableTypes.set(key, t);
					for(ef in en.constructs) {
						switch(Context.follow(ef.type)) {
							case TFun(args, _):
								for(a in args) recordAggregateType(a.t);
							case _:
						}
					}
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
			case TEnum(e, params):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				owner != null ? en.pack.concat([owner]).join(".") : en.module + "." + en.name;
			case _: "Unknown";
		};
	}

	/**
		The comparator a sorted builder binds at creation, per key domain
		(stdlib/07): integers take the resident comparator reference,
		strings compare with the platform operator (the ruled UTF-16
		code-unit order), structures take the per-type generated
		comparison. The explicit type arguments at the call site make the
		reference and lambda parameter types resolve.
	**/
	function sortedComparator(externModule: String, kType: Null<Type>, pos: haxe.macro.Expr.Position): String {
		if(kType == null) {
			Context.error("sorted builder requires an explicit key type", pos);
		}
		imports.requireType(externModule, "SortedTable");
		return switch(KotlinType.classifyKey(kType, pos)) {
			case IntKey: "SortedTable::compareInts";
			case StringKey: "SortedTable::compareStrings";
			case StructKey(def, _):
				imports.requireType(def.module, "compare");
				"::compare";
		};
	}

	function fail(e: Null<TypedExpr>, message: String): Dynamic {
		final pos = e != null ? e.pos : Context.currentPos();
		Context.error("kotlin target: " + message, pos);
		return null;
	}
}
#end
