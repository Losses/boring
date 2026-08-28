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

	/** Locals reassigned after their declaration; emitted with var. */
	final mutated: Map<Int, Bool> = [];

	/** Fill arrays returning as asList() when decodeBoundary holds. */
	final asListReturn: Map<Int, String> = [];

	/** Names used by parameters and locals; generated names avoid them. */
	final usedNames: Map<String, Bool> = [];

	final hiddenNames: Map<Int, String> = [];
	var hiddenCounter: Int = 0;

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

	// ------------------------------------------------------------------
	// Function bodies
	// ------------------------------------------------------------------

	public function functionBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) {
			Context.error("function field has no body to lower", f.field.pos);
		}
		DefaultArgExpander.completeRootExpr(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
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

	public function constructorBody(className: String, f: ClassFuncData, isException: Bool): Array<String> {
		if(f.expr == null) {
			Context.error("constructor has no body to lower", f.field.pos);
		}
		scanLocals(f.expr);
		final stmts = statementsOf(f.expr);
		final out: Array<String> = [];
		for(s in stmts) {
			for(l in stmtLines(s, 1)) out.push(l);
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
		};
	}

	function stmtLines(e: TypedExpr, depth: Int): Array<String> {
		switch(e.expr) {
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
				return [indent(depth) + '$kw ${localName(v)}$typeAnn = ${expr(init)}'];
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
			case TReturn(ret) if(ret == null):
				return [indent(depth) + "return"];
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
			case TBreak:
				return [indent(depth) + "break"];
			case TContinue:
				return [indent(depth) + "continue"];
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

	/** Renders `Owner.Variant` or `Owner.Variant(args)` for an exception construction over its payload enum. */
	function exceptionVariant(cls: ClassType, payloadArg: TypedExpr): String {
		final owner = state.payloadEnumOwners.get(state.exceptionPayloads.get(cls.module));
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
		switch(e.expr) {
			case TConst(c):
				switch(c) {
					case TInt(v): return Std.string(v);
					case TFloat(f): return Std.string(f);
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
				return expr(arr) + "[" + expr(idx) + "]";
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
				return expr(se) + "." + payloadName(ef, index);
			case TEnumIndex(_):
				return fail(e, "enum index only lowers inside a variant switch");
			case TFunction(f):
				final params = [for(a in f.args) '${a.v.name}: ${types.of(a.v.t)}'].join(", ");
				final ret = types.of(f.t);
				final retStr = ret == "Unit" ? "" : ": " + ret;
				return 'fun($params)$retStr {\n' + blockLines(statementsOf(f.expr), 1).join("\n") + '\n}';
			case TIf(c, t, f) if(f != null):
				return "(if (" + expr(c) + ") " + expr(t) + " else " + expr(f) + ")";
			case _:
				return fail(e, "expression has no Kotlin lowering in the subset: " + Std.string(e.expr));
		}
	}

	function binop(e: TypedExpr, op: Binop, l: TypedExpr, r: TypedExpr): String {
		switch(op) {
			case OpAssign:
				return assignTarget(l) + " = " + expr(r);
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
				if(!isStringType(l.t)) {
					return "(" + operand(l, op, false) + ").toString() + " + operand(r, op, true);
				}
				return operand(l, op, false) + " + " + operand(r, op, true);
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
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "String":
				return "String." + name;
			case "Math":
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
				imports.requireType("std.SortedMap", "SortedMap");
				return "SortedMap." + name;
			case "std.SortedSet":
				imports.requireType("std.SortedSet", "SortedSet");
				return "SortedSet." + name;
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
					imports.requireType("std.SortedMap", "SortedMap");
					return "SortedMap." + name;
				}
				if(cls.module == "std.SortedSet") {
					imports.requireType("std.SortedSet", "SortedSet");
					return "SortedSet." + name;
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

	function call(fn: TypedExpr, args: Array<TypedExpr>): String {
		switch(fn.expr) {
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final name = cf.get().name;
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
		final renderedArgs = [for(a in args) expr(a)].join(", ");
		switch(fn.expr) {
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return expr(subj) + ".length";
			case TField(subj, FInstance(_, _, cf)):
				final name = cf.get().name;
				if(isStringBuf(subj)) {
					if(name == "add") {
						return expr(subj) + ".append(" + expr(args[0]) + ")";
					}
					if(name == "addChar") {
						return expr(subj) + ".append((" + expr(args[0]) + ").toChar())";
					}
					if(name == "toString") {
						return expr(subj) + ".toString()";
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
					// is dropped instead of rendered.
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
					final domain = KotlinType.classifyKey(kType, fn.pos);
					switch(domain) {
						case IntKey:
							imports.requireType("std.SortedMap", "SortedMap");
							return "SortedMap.builder<" + types.of(vType) + ">()";
						case StringKey:
							imports.requireType("std.SortedMap", "SortedMapStr");
							return "SortedMapStr.builder<" + types.of(vType) + ">()";
						case StructKey(def, _):
							imports.requireType("std.SortedMap", "SortedMapObj");
							imports.requireType(def.module, "compare");
							return "SortedMapObj.builder<" + types.of(kType) + ", " + types.of(vType) + ">(::compare)";
					}
				}
				if(cls.pack.join(".") == "std" && cls.name == "SortedSet" && name == "builder") {
					final kType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
						case _: null;
					};
					final domain = KotlinType.classifyKey(kType, fn.pos);
					switch(domain) {
						case IntKey:
							imports.requireType("std.SortedSet", "SortedSet");
							return "SortedSet.builder()";
						case StringKey:
							imports.requireType("std.SortedSet", "SortedSetStr");
							return "SortedSetStr.builder()";
						case StructKey(def, _):
							imports.requireType("std.SortedSet", "SortedSetObj");
							imports.requireType(def.module, "compare");
							return "SortedSetObj.builder<" + types.of(kType) + ">(::compare)";
					}
				}

				return staticRef(cls, name) + "(" + renderedArgs + ")";
			case TField(subj, FEnum(e, ef)):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				if(owner != null) {
					return owner + "." + ef.name + "(" + renderedArgs + ")";
				}
				imports.requireType(en.module, en.name);
				return en.name + "." + ef.name + "(" + renderedArgs + ")";
			case TConst(TSuper):
				return "super(" + renderedArgs + ")";
			case _:
				return expr(fn) + "(" + renderedArgs + ")";
		}
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final renderedArgs = [for(a in args) expr(a)].join(", ");
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return "StringBuilder()";
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

	function assignTarget(e: TypedExpr): String {
		switch(e.expr) {
			case TArray(arr, idx):
				return expr(arr) + "[" + expr(idx) + "]";
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
			case TVar(v, _):
				if(v.name != "`") {
					usedNames.set(v.name, true);
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

	function fail(e: Null<TypedExpr>, message: String): Dynamic {
		final pos = e != null ? e.pos : Context.currentPos();
		Context.error("kotlin target: " + message, pos);
		return null;
	}
}
#end
