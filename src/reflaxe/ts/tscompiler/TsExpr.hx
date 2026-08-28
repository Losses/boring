package tscompiler;

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
	Statement and expression lowering from the Haxe typed AST to
	TypeScript. Every lowering here is named after the ruling that
	requires it and derived from the shapes the typer actually produces
	(counted for loops arrive as two hidden TVar statements plus a
	TWhile; the loop variable is captured through a post-increment of
	the hidden counter).

	- features/09 IntervalLoopRecognition: the counted loop re-emits as
	  `for (let i = a; i < b; i += 1)`.
	- features/09 LengthHoist: a `.length` bound is read once. With an
	  earlier reader in the block it becomes a const placed before that
	  reader; read only by the loop, it folds into the for-init as a
	  comma declaration.
	- features/09 CountedFillLowering: a fresh `new Array<T>()` filled
	  by a counted loop whose body only stores elements (indexed store
	  or one push) is emitted as `new Array<T>(bound)` plus indexed
	  stores.
	- features/18 DecodeBoundaryFreeze: functions returning
	  ReadOnlyArray freeze the records they build, per stored record
	  (including nested records) and at the return.
	- stdlib/03 enum lowering: variants become `{ kind: "Name", ... }`
	  objects; variant switches dispatch on `kind`.
	- stdlib/04 ConstantAsciiFold: writeAscii of an all-ASCII constant
	  of width 4 or 2 folds to writeU32/writeU16 of the packed
	  big-endian word.
	- stdlib/01: haxe.io.Bytes.get(i) lowers to a Uint8Array index
	  read; haxe.io.FPHelper bit conversions lower to the runtime
	  helpers (stdlib/05).
**/
class TsExpr {
	final imports: TsImports;
	final types: TsType;

	/** True while emitting a function whose return type is ReadOnlyArray. */
	var decodeBoundary: Bool = false;

	/** Enum-capture locals mapped to the payload expression they stand for. */
	final subst: Map<Int, String> = [];

	/** Hoisted bound names active for a statement range. */
	final boundSubst: Map<Int, String> = [];

	/** Locals reassigned after their declaration; emitted with let. */
	final mutated: Map<Int, Bool> = [];

	/** Fill arrays frozen at the return when decodeBoundary holds. */
	final frozenFill: Map<Int, Bool> = [];

	/** Names used by parameters and locals; generated names avoid them. */
	final usedNames: Map<String, Bool> = [];

	final hiddenNames: Map<Int, String> = [];
	var hiddenCounter: Int = 0;
	var hoistCounter: Int = 0;

	public function new(imports: TsImports, types: TsType) {
		this.imports = imports;
		this.types = types;
	}

	public function reserveName(name: String): Void {
		usedNames.set(name, true);
	}

	public function setDecodeBoundary(value: Bool): Void {
		decodeBoundary = value;
	}

	/** Expression entry for callers holding a bare typed expression. */
	public function expressionOf(e: TypedExpr): String {
		return expr(e);
	}

	/** Statement-level entry for framework-initiated compiles. */
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

		scanLocals(f.expr);
		return blockLines(statementsOf(f.expr), 2);
	}

	/**
		Constructor body. TypeScript requires super() before any this
		access; Haxe allows field assignments before the super call, so
		the super call moves first. Subclasses of haxe.Exception also
		stamp this.name with the class name (stdlib/03).
	**/
	public function constructorBody(className: String, f: ClassFuncData, isException: Bool): Array<String> {
		if(f.expr == null) {
			Context.error("constructor has no body to lower", f.field.pos);
		}
		scanLocals(f.expr);
		final stmts = statementsOf(f.expr);
		final out: Array<String> = [];
		var superIdx = -1;
		for(i in 0...stmts.length) {
			switch(stmts[i].expr) {
				case TCall({expr: TConst(TSuper)}, _): superIdx = i;
				case _:
			}
		}
		if(superIdx < 0 && isException) {
			out.push(indent(2) + "super();");
		}
		if(superIdx >= 0) {
			for(l in stmtLines(stmts[superIdx], 2)) out.push(l);
		}
		if(isException) {
			out.push(indent(2) + 'this.name = "$className";');
		}
		for(i in 0...stmts.length) {
			if(i == superIdx) {
				continue;
			}
			for(l in stmtLines(stmts[i], 2)) out.push(l);
		}
		return out;
	}

	// ------------------------------------------------------------------
	// Statements
	// ------------------------------------------------------------------

	function statementsOf(e: TypedExpr): Array<TypedExpr> {
		return switch(e.expr) {
			case TBlock(stmts): stmts;
			case _: [e];
		}
	}

	function stmtLines(e: TypedExpr, depth: Int): Array<String> {
		switch(e.expr) {
			case TVar(v, init) if(init != null):
				final kw = mutated.exists(v.id) ? "let" : "const";
				return [indent(depth) + '$kw ${localName(v)} = ${expr(init)};'];
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
				return [indent(depth) + "return;"];
			case TReturn(ret):
				final inner = stripWrap(ret);
				switch(inner.expr) {
					case TSwitch(_, _, _):
						return switchReturn(inner, depth);
					case TLocal(v) if(frozenFill.exists(v.id)):
						return [indent(depth) + "return Object.freeze(" + localName(v) + ");"];
					case _:
						return [indent(depth) + "return " + expr(ret) + ";"];
				}
			case TThrow(x):
				return [indent(depth) + "throw " + expr(x) + ";"];
			case TBreak:
				return [indent(depth) + "break;"];
			case TContinue:
				return [indent(depth) + "continue;"];
			case TMeta(_, inner):
				return stmtLines(inner, depth);
			case _:
				return [indent(depth) + expr(e) + ";"];
		}
	}

	function isVarAssigned(e: TypedExpr, varId: Int): Bool {
		var found = false;
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
					switch(stripCast(t).expr) {
						case TLocal(v) if(v.id == varId): found = true;
						case _:
					}
				case _:
			}
			TypedExprTools.iter(x, walk);
		}
		walk(e);
		return found;
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
						var otherAssign = false;
						for(s in stmts) {
							if(isVarAssigned(s, v.id)) {
								otherAssign = true;
								break;
							}
						}
						if(!otherAssign) {
							mutated.remove(v.id);
						}
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

		// features/09 LengthHoist: counted loops whose bound reads
		// subject.length hoist that read into a single read placed
		// before its first use. A bound with an earlier reader becomes
		// a block const ahead of that reader; a bound read only by the
		// loop folds into the for-init as a comma declaration, so it
		// never occupies a block-level name.
		final hoists: Array<{firstUse: Int, loopAt: Int, subject: TVar, name: String}> = [];
		for(i in 0...stmts.length) {
			final loop = matchInterval(stmts[i]);
			if(loop == null) {
				continue;
			}
			final subject = boundLengthSubject(loop.bound);
			if(subject == null || hoistedFor(hoists, subject) != null) {
				continue;
			}
			var firstUse = i;
			for(j in 0...i) {
				if(usesLengthOf(stmts[j], subject)) {
					firstUse = j;
					break;
				}
			}
			hoists.push({firstUse: firstUse, loopAt: i, subject: subject, name: freshHoistName()});
		}

		var i = 0;
		while(i < stmts.length) {
			// A hoist with an earlier reader keeps its block const at
			// that reader, so the read happens exactly once.
			for(h in hoists) {
				if(h.firstUse == i && h.firstUse != h.loopAt) {
					boundSubst.set(h.subject.id, h.name);
					out.push(indent(depth) + "const " + h.name + " = " + localName(h.subject) + ".length;");
				}
			}
			final fused = fillFusion(stmts, i, depth, hoists);
			if(fused != null) {
				for(h in hoists) {
					if(h.loopAt == i + 1 && h.firstUse == h.loopAt) {
						boundSubst.set(h.subject.id, h.name);
						out.push(indent(depth) + "const " + h.name + " = " + localName(h.subject) + ".length;");
					}
				}
				for(l in fused) out.push(l);
				clearHoistsAt(hoists, i + 1);
				i += 2;
				continue;
			}
			final loop = matchInterval(stmts[i]);
			if(loop != null) {
				// A bound with no earlier reader folds into the for-init
				// as a comma declaration instead of a block-level const.
				var fold: Null<String> = null;
				for(h in hoists) {
					if(h.loopAt == i && h.firstUse == i) {
						boundSubst.set(h.subject.id, h.name);
						fold = h.name + " = " + localName(h.subject) + ".length";
					}
				}
				for(l in loopLines(loop, depth, fold)) out.push(l);
				clearHoistsAt(hoists, i);
				i += 1;
				continue;
			}
			for(l in stmtLines(stmts[i], depth)) out.push(l);
			clearHoistsAt(hoists, i);
			i += 1;
		}
		return out;
	}

	function clearHoistsAt(hoists: Array<{firstUse: Int, loopAt: Int, subject: TVar, name: String}>, at: Int): Void {
		for(h in hoists) {
			if(h.loopAt == at) {
				boundSubst.remove(h.subject.id);
			}
		}
	}

	// ------------------------------------------------------------------
	// Counted loops (features/09)
	// ------------------------------------------------------------------

	/**
		The typer flattens a counted for-loop when it sits directly in a
		statement list: the counter declaration, bound declaration, and
		while land as three sibling statements with no wrapping block.
		Regrouping restores the block form the loop lowerings match on.
	**/
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

	function boundLengthSubject(bound: TypedExpr): Null<TVar> {
		final inner = stripWrap(bound);
		switch(inner.expr) {
			case TField(subj, fa) if(fieldName(fa) == "length"):
				switch(stripWrap(subj).expr) {
					case TLocal(v): return v;
					case _: return null;
				}
			case _: return null;
		}
	}

	function loopLines(loop, depth: Int, fold: Null<String>): Array<String> {
		final name = loop.index.name;
		final init = "let " + name + " = " + expr(loop.start) + (fold != null ? ", " + fold : "");
		final out = [
			indent(depth) + "for (" + init + "; " + name + " < " + expr(loop.bound) + "; " + name + " += 1) {"
		];
		for(l in blockLines(loop.body, depth + 1)) out.push(l);
		out.push(indent(depth) + "}");
		return out;
	}

	function hoistedFor(hoists: Array<{firstUse: Int, loopAt: Int, subject: TVar, name: String}>, subject: TVar): Null<String> {
		for(h in hoists) {
			if(h.subject.id == subject.id) {
				return h.name;
			}
		}
		return null;
	}

	function freshHoistName(): String {
		while(true) {
			hoistCounter += 1;
			final base = hoistCounter == 1 ? "count" : "count" + hoistCounter;
			if(!usedNames.exists(base)) {
				return base;
			}
		}
	}

	function usesLengthOf(e: TypedExpr, subject: TVar): Bool {
		var found = false;
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TField(subj, fa) if(fieldName(fa) == "length"):
					final target = stripWrap(subj);
					switch(target.expr) {
						case TLocal(v) if(v.id == subject.id): found = true;
						case _:
					}
				case _:
			}
			TypedExprTools.iter(x, walk);
		}
		walk(e);
		return found;
	}

	// ------------------------------------------------------------------
	// Counted fill (features/09) and decode freeze (features/18)
	// ------------------------------------------------------------------

	/**
		CountedFillLowering: `TVar arr = new Array<T>()` immediately
		followed by a counted loop whose only use of arr is storing one
		element per iteration (an indexed store at the loop index, or a
		single push) becomes `new Array<T>(bound)` with indexed stores.
	**/
	function fillFusion(stmts: Array<TypedExpr>, i: Int, depth: Int, hoists: Array<{firstUse: Int, loopAt: Int, subject: TVar, name: String}>): Null<Array<String>> {
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

		final elem = types.of(alloc.elem);
		final arrName = localName(alloc.arr);
		final subject = boundLengthSubject(loop.bound);
		final hoistName = subject != null ? hoistedFor(hoists, subject) : null;
		final allocBound = hoistName != null ? hoistName : allocationBound(loop.bound);
		final condBound = hoistName != null ? hoistName : expr(loop.bound);
		final name = loop.index.name;
		final out: Array<String> = [];
		out.push(indent(depth) + 'const $arrName: ${elem}[] = new Array<$elem>($allocBound);');
		out.push(indent(depth) + "for (let " + name + " = " + expr(loop.start) + "; " + name + " < " + condBound + "; " + name + " += 1) {");
		final nonStores: Array<TypedExpr> = [];
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + "[" + name + "] = " + fillValue(store.value) + ";");
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + "[" + name + "] = " + fillValue(push.arg) + ";");
				continue;
			}
			nonStores.push(s);
		}
		if(nonStores.length > 0) {
			for(l in blockLines(nonStores, depth + 1)) out.push(l);
		}
		out.push(indent(depth) + "}");
		if(decodeBoundary) {
			frozenFill.set(alloc.arr.id, true);
		}
		return out;
	}

	/**
		Allocation bound safety: `new Array(n)` throws RangeError for a
		negative n while the counted loop `i < n` would skip outright, so
		a bound that is not structurally non-negative (a `.length` read or
		a non-negative Int constant) is clamped. Without this a decoded
		count of -1 (0xFFFFFFFF read as signed Int32) raises RangeError
		where Haxe falls through to the trailing-bytes check.
	**/
	function allocationBound(bound: TypedExpr): String {
		final text = expr(bound);
		return switch(stripWrap(bound).expr) {
			case TConst(TInt(n)) if(n >= 0): text;
			case TField(_, fa) if(fieldName(fa) == "length"): text;
			case _: "Math.max(" + text + ", 0)";
		}
	}

	/** features/18 DecodeBoundaryFreeze wraps record literals stored into a decode fill. */
	function fillValue(value: TypedExpr): String {
		final inner = stripWrap(value);
		switch(inner.expr) {
			case TObjectDecl(fields) if(decodeBoundary): return objectLiteral(fields, true);
			case _: return expr(value);
		}
	}

	/** `arr[idx] = value` matcher, wrapper-tolerant. */
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

	/** `arr.push(arg)` matcher, wrapper-tolerant. */
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
					case _: return fail(e, "constant has no TypeScript lowering");
				}
			case TLocal(v):
				if(subst.exists(v.id)) {
					return subst.get(v.id);
				}
				return localName(v);
			case TArray(arr, idx):
				return expr(arr) + "[" + expr(idx) + "]!";
			case TBinop(op, l, r):
				return binop(e, op, l, r);
			case TUnop(op, post, subj):
				return unop(e, op, subj);
			case TField(subj, fa):
				return field(subj, fa);
			case TTypeExpr(t):
				return typeExpr(t);
			case TParenthesis(inner):
				return expr(inner);
			case TObjectDecl(fields):
				return objectLiteral(fields, false);
			case TArrayDecl(elems):
				return "[" + [for(x in elems) expr(x)].join(", ") + "]";
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
				return '($params): $ret => {\n' + blockLines(statementsOf(f.expr), 2).join("\n") + '\n}';
			case TIf(c, t, f) if(f != null):
				return "(" + expr(c) + " ? " + expr(t) + " : " + expr(f) + ")";
			case _:
				return fail(e, "expression has no TypeScript lowering in the subset");
		}
	}

	function isEnumConstruct(e: TypedExpr): Null<EnumField> {
		if(e == null) return null;
		return switch(stripWrap(e).expr) {
			case TField(_, FEnum(_, ef)): ef;
			case _: null;
		};
	}

	function binop(e: TypedExpr, op: Binop, l: TypedExpr, r: TypedExpr): String {
		switch(op) {
			case OpAssign:
				return assignTarget(l) + " = " + expr(r);
			case OpAssignOp(inner):
				return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
			case OpAdd:
				if(isStringLeaf(l)) {
					return templateLiteral(l, r);
				}
				return operand(l, op, false) + " + " + operand(r, op, true);
			case OpEq | OpNotEq:
				final sym = op == OpEq ? "===" : "!==";
				final leftEnum = isEnumConstruct(l);
				final rightEnum = isEnumConstruct(r);
				if(leftEnum != null && rightEnum == null) {
					return expr(r) + ".kind " + sym + ' "${leftEnum.name}"';
				}
				if(rightEnum != null && leftEnum == null) {
					return expr(l) + ".kind " + sym + ' "${rightEnum.name}"';
				}
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
			case _:
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
		}
	}

	function operand(e: TypedExpr, parent: Binop, isRight: Bool): String {
		final rendered = expr(e);
		switch(stripWrap(e).expr) {
			case TBinop(op, _, _):
				final cp = precedenceOf(op);
				final pp = precedenceOf(parent);
				var parens = cp < pp || (cp == pp && isRight && !associative(op));
				if(!parens && isShift(op) && isBitwiseLogical(parent)) {
					// Style: keep shift operands parenthesized under
					// bitwise-logical operators, matching the hand-written tree.
					parens = true;
				}
				return parens ? "(" + rendered + ")" : rendered;
			case _:
				return rendered;
		}
	}

	function unop(e: TypedExpr, op: Unop, subj: TypedExpr): String {
		final inner = expr(subj);
		final wrapped = switch(stripWrap(subj).expr) {
			case TBinop(_, _, _): "(" + inner + ")";
			case _: inner;
		}
		switch(op) {
			case OpNot: return "!" + wrapped;
			case OpNeg: return "-" + wrapped;
			case _: {
				final infos = Context.getPosInfos(e.pos);
				return fail(e, "unary operator has no lowering in the subset: " + Std.string(op) + " at " + infos.file + ":" + infos.min);
			}
		}
	}

	function field(subj: TypedExpr, fa: FieldAccess): String {
		switch(fa) {
			case FStatic(c, cf):
				return staticRef(c.get(), cf.get().name);
			case FEnum(_, ef):
				return "{ kind: \"" + ef.name + "\" }";
			case FInstance(_, _, cf) | FAnon(cf):
				final name = cf.get().name;
				final target = stripCast(subj);
				switch(target.expr) {
					case TLocal(v) if(name == "length" && boundSubst.exists(v.id)):
						return boundSubst.get(v.id);
					case _:
				}
				return expr(subj) + "." + name;
			case FDynamic(name):
				if((name == "length" || name == "get_length") && isStringBuf(subj)) {
					return expr(subj) + ".length";
				}
				return fail(subj, "dynamic field access has no lowering: " + name);
			case FClosure(_):
				return fail(subj, "function value has no lowering (V08)");
		}
	}

	function staticRef(cls: ClassType, name: String): String {
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "String":
				return "String." + name;
			case "Math":
				if(name == "NaN") return "Number.NaN";
				if(name == "POSITIVE_INFINITY") return "Infinity";
				if(name == "NEGATIVE_INFINITY") return "-Infinity";
				return "Math." + name;
			case "Std":
				if(name == "int") return "Math.trunc";
				if(name == "string") return "String";
				return "Std." + name;
			case "haxe.io.FPHelper":
				// stdlib/05: the bit conversions live in the runtime module.
				imports.runtime(name);
				return name;
			case "std.Test" | "std.__test_shim":
				imports.runtimeTest("Test");
				return "Test." + name;
			case "std.SortedMap":
				imports.runtime("SortedMap");
				return "SortedMap." + name;
			case "std.SortedSet":
				imports.runtime("SortedSet");
				return "SortedSet." + name;
			case "std.UStringRT":
				imports.runtime("UString");
				return "UString." + name;
			case "std.Graphemes":
				imports.runtime("Graphemes");
				return "Graphemes." + name;
			case _:
				if(cls.module == "std.Test") {
					imports.runtimeTest("Test");
					return "Test." + name;
				}
				if(cls.module == "std.SortedMap") {
					imports.runtime("SortedMap");
					return "SortedMap." + name;
				}
				if(cls.module == "std.SortedSet") {
					imports.runtime("SortedSet");
					return "SortedSet." + name;
				}
				if(cls.module == "std.UStringRT") {
					imports.runtime("UString");
					return "UString." + name;
				}
				if(cls.module == "std.Graphemes") {
					imports.runtime("Graphemes");
					return "Graphemes." + name;
				}
				for(field in cls.statics.get()) {
					if(field.name == name && DataTableHelper.isDataTableField(field)) {
						return name;
					}
				}
				imports.value(cls.module, cls.name);
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
					imports.runtimeTest("Test");
					return "Test";
				}
				imports.value(cls.module, cls.name);
				return cls.name;
				Context.error("type expression has no value lowering: " + cls.name, Context.currentPos());
				return null;
			case TEnumDecl(e):
				final en = e.get();
				imports.value(en.module, en.name);
				return en.name;
				Context.error("enum type expression has no value lowering: " + en.name, Context.currentPos());
				return null;
			case _:
				Context.error("type expression has no value lowering", Context.currentPos());
				return null;
		}
	}

	function call(fn: TypedExpr, args: Array<TypedExpr>): String {
		switch(fn.expr) {
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final fName = cf.get().name;
				if((cls.name == "Functional" || cls.name == "__functional_shim" || cls.module == "std.Functional" || cls.pack.join(".") + "." + cls.name == "std.Functional") && fName == "sortedBy") {
					final receiver = args[0];
					final lambda = args[1];
					final func = unwrapLambda(lambda);
					if(func != null && func.args.length == 1) {
						final paramVar = func.args[0].v;
						final bodyExpr = lambdaBody(func.expr);
						subst.set(paramVar.id, "_a");
						final keyA = expr(bodyExpr);
						subst.set(paramVar.id, "_b");
						final keyB = expr(bodyExpr);
						subst.remove(paramVar.id);
						return expr(receiver) + ".slice().sort((_a, _b) => { const _ka = " + keyA + "; const _kb = " + keyB + "; return _ka < _kb ? -1 : (_ka > _kb ? 1 : 0); })";
					}
				}
			case _:
		}
		final rendered = [for(a in args) expr(a)].join(", ");
		switch(fn.expr) {
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return expr(subj) + ".length";
			case TField(subj, FInstance(_, _, cf)):
				final name = cf.get().name;
				if(isStringBuf(subj)) {
					if(name == "add") {
						return expr(subj) + " += " + expr(args[0]);
					}
					if(name == "addChar") {
						return expr(subj) + " += String.fromCharCode(" + expr(args[0]) + ")";
					}
					if(name == "toString") {
						return expr(subj);
					}
					if(name == "get_length" || name == "length") {
						return expr(subj) + ".length";
					}
				}
				final folded = constantAsciiFold(subj, name, args);
				if(folded != null) {
					return folded;
				}
				// stdlib/01: Bytes.get(i) is a Uint8Array index read.
				if(name == "get" && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + "]!";
				}
				return expr(subj) + "." + name + "(" + rendered + ")";
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final fName = cf.get().name;
		
				if((cls.module == "std.SortedMap" || cls.pack.join(".") + "." + cls.name == "std.SortedMap") && fName == "builder") {
					final kType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
						case _: null;
					};
					final vType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 1): params[1];
						case _: null;
					};
					final domain = TsType.classifyKey(kType, fn.pos);
					switch(domain) {
						case IntKey:
							imports.runtime("SortedMap");
							return "SortedMap.builder<" + types.of(vType) + ">()";
						case StringKey:
							imports.runtime("SortedMapStr");
							return "SortedMapStr.builder<" + types.of(vType) + ">()";
						case StructKey(def, _):
							imports.runtime("SortedMapByKey");
							final cmpName = "compare" + def.name;
							imports.value(def.module, cmpName);
							return "SortedMapByKey.builder<" + types.of(kType) + ", " + types.of(vType) + ">(" + cmpName + ")";
					}
				}
				if((cls.module == "std.SortedSet" || cls.pack.join(".") + "." + cls.name == "std.SortedSet") && fName == "builder") {
					final kType = switch(fn.t) {
						case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
						case _: null;
					};
					final domain = TsType.classifyKey(kType, fn.pos);
					switch(domain) {
						case IntKey:
							imports.runtime("SortedSet");
							return "SortedSet.builder()";
						case StringKey:
							imports.runtime("SortedSetStr");
							return "SortedSetStr.builder()";
						case StructKey(def, _):
							imports.runtime("SortedSetByKey");
							final cmpName = "compare" + def.name;
							imports.value(def.module, cmpName);
							return "SortedSetByKey.builder<" + types.of(kType) + ">(" + cmpName + ")";
					}
				}
				return staticRef(c.get(), cf.get().name) + "(" + rendered + ")";
			case TField(_, FEnum(_, ef)):
				return enumConstruct(ef, args);
			case TConst(TSuper):
				return "super(" + rendered + ")";
			case _:
				return expr(fn) + "(" + rendered + ")";
		}
	}

	/** stdlib/04 ConstantAsciiFold: writeAscii of a width-4 or width-2 ASCII constant packs into one word write. */
	function constantAsciiFold(subj: TypedExpr, name: String, args: Array<TypedExpr>): Null<String> {
		if(name != "writeAscii" || args.length != 1) {
			return null;
		}
		final s = switch(args[0].expr) {
			case TConst(TString(v)): v;
			case _: return null;
		}
		if(s.length != 4 && s.length != 2) {
			return null;
		}
		var word = 0;
		for(i in 0...s.length) {
			final code = s.charCodeAt(i);
			if(code > 255) {
				return null;
			}
			word = word * 256 + code;
		}
		final method = s.length == 4 ? "writeU32" : "writeU16";
		final digits = s.length == 4 ? 8 : 4;
		return expr(subj) + "." + method + "(0x" + StringTools.hex(word, digits) + ")";
	}

	function enumConstruct(ef: EnumField, args: Array<TypedExpr>): String {
		final parts = ['kind: "${ef.name}"'];
		final names = payloadNames(ef);
		for(i in 0...args.length) {
			final pname = i < names.length ? names[i] : "v" + i;
			final shorthand = switch(args[i].expr) {
				case TLocal(v): v.name == pname;
				case _: false;
			}
			if(shorthand) {
				parts.push(pname);
			} else {
				parts.push(pname + ": " + expr(args[i]));
			}
		}
		return "{ " + parts.join(", ") + " }";
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final rendered = [for(a in args) expr(a)].join(", ");
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return '""';
			case "haxe.io.BytesBuffer":
				imports.runtime("BytesBuffer");
				return "new BytesBuffer(" + rendered + ")";
			case "Array":
				return "new Array<" + types.of(params[0]) + ">(" + rendered + ")";
			case _:
				imports.value(cls.module, cls.name);
				return "new " + cls.name + "(" + rendered + ")";
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
				return fail(e, "assignment target has no TypeScript lowering");
		}
	}

	function objectLiteral(fields: Array<{name: String, expr: TypedExpr}>, freeze: Bool): String {
		final parts = [];
		for(f in fields) {
			final shorthand = switch(f.expr.expr) {
				case TLocal(v): v.name == f.name;
				case _: false;
			}
			if(shorthand) {
				parts.push(f.name);
			} else if(freeze) {
				parts.push(f.name + ": " + frozenValue(f.expr));
			} else {
				parts.push(f.name + ": " + expr(f.expr));
			}
		}
		final core = "{ " + parts.join(", ") + " }";
		return freeze ? "Object.freeze(" + core + ")" : core;
	}

	function frozenValue(e: TypedExpr): String {
		final inner = stripCast(e);
		switch(inner.expr) {
			case TObjectDecl(fields): return objectLiteral(fields, true);
			case _: return expr(e);
		}
	}

	// ------------------------------------------------------------------
	// Variant switches (stdlib/03)
	// ------------------------------------------------------------------

	function switchReturn(sw: TypedExpr, depth: Int): Array<String> {
		final switchParts = switch(sw.expr) {
			case TSwitch(subj, cases, def): {subj: subj, cases: cases, def: def};
			case _: return fail(sw, "not a switch");
		}
		final subj = stripWrap(switchParts.subj);
		final se = switch(subj.expr) {
			case TEnumIndex(inner): inner;
			case _: return fail(sw, "switch subject is not a variant index");
		}
		final subjRendered = expr(se);
		final table = enumTable(se);
		final out = [indent(depth) + "switch (" + subjRendered + ".kind) {"];
		for(c in switchParts.cases) {
			final index = switch(c.values[0].expr) {
				case TConst(TInt(v)): v;
				case _: return fail(sw, "variant switch case is not a constant index");
			}
			final info = table.get(index);
			if(info == null) {
				return fail(sw, "variant switch case index has no construct");
			}
			out.push(indent(depth) + '  case "${info.name}":');
			for(l in armLines(c.expr, depth + 2)) out.push(l);
		}
		if(switchParts.def != null) {
			return fail(sw, "variant switch carries a default arm (V15)");
		}
		out.push(indent(depth) + "}");
		return out;
	}

	function armLines(e: TypedExpr, depth: Int): Array<String> {
		final out: Array<String> = [];
		var value: Null<String> = null;
		function walk(stmts: Array<TypedExpr>) {
			for(s in stmts) {
				switch(s.expr) {
					case TVar(v, init):
						if(init == null) {
							Context.error("ts target: declaration without initializer has no lowering", s.pos);
						}
						switch(stripWrap(init).expr) {
							case TEnumParameter(se, ef, index):
								subst.set(v.id, expr(se) + "." + payloadName(ef, index));
							case TLocal(source) if(subst.exists(source.id)):
								// The typer binds the switch subject to a hidden
								// local before extracting the payload; forward
								// the substitution through that chain.
								subst.set(v.id, subst.get(source.id));
							case _:
								out.push(indent(depth) + "const " + localName(v) + " = " + expr(init) + ";");
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
			return fail(e, "variant switch arm has no value");
		}
		out.push(indent(depth) + "return " + value + ";");
		return out;
	}

	function enumTable(se: TypedExpr): Map<Int, {name: String}> {
		final table = new Map<Int, {name: String}>();
		switch(se.t) {
			case TEnum(e, _):
				final en = e.get();
				for(name => ef in en.constructs) {
					table.set(ef.index, {name: ef.name});
				}
			case _:
				return fail(se, "variant switch subject is not a variant value");
		}
		return table;
	}

	function payloadNames(ef: EnumField): Array<String> {
		return switch(ef.type) {
			case TFun(args, _): [for(a in args) a.name];
			case _: [];
		}
	}

	function payloadName(ef: EnumField, index: Int): String {
		final names = payloadNames(ef);
		return index < names.length ? names[index] : "v" + index;
	}

	// ------------------------------------------------------------------
	// String interpolation
	// ------------------------------------------------------------------

	function isStringLeaf(e: TypedExpr): Bool {
		switch(e.expr) {
			case TConst(TString(_)): return true;
			case TBinop(OpAdd, l, _): return isStringLeaf(l);
			case _: return false;
		}
	}

	function templateLiteral(l: TypedExpr, r: TypedExpr): String {
		final leaves: Array<TypedExpr> = [];
		flattenAdd(l, leaves);
		leaves.push(r);
		final b = new StringBuf();
		b.addChar("`".code);
		for(leaf in leaves) {
			switch(leaf.expr) {
				case TConst(TString(s)): b.add(escapeTemplate(s));
				case _: b.add("${" + expr(leaf) + "}");
			}
		}
		b.addChar("`".code);
		return b.toString();
	}

	function flattenAdd(e: TypedExpr, into: Array<TypedExpr>): Void {
		switch(e.expr) {
			case TBinop(OpAdd, a, b):
				flattenAdd(a, into);
				into.push(b);
			case _:
				into.push(e);
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
			case TCall(fn, _):
				switch(fn.expr) {
					case TField(subj, FInstance(_, _, cf)):
						final n = cf.get().name;
						if(isStringBuf(subj) && (n == "add" || n == "addChar")) {
							switch(stripWrap(subj).expr) {
								case TLocal(v): mutated.set(v.id, true);
								case _:
							}
						}
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
		final candidates = ["i", "j", "k", "n", "m"];
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
	// Operators, predicates, and rendering helpers
	// ------------------------------------------------------------------

	function symbolOf(op: Binop): String {
		return switch(op) {
			case OpAdd: "+";
			case OpMult: "*";
			case OpDiv: "/";
			case OpSub: "-";
			case OpEq: "===";
			case OpNotEq: "!==";
			case OpGt: ">";
			case OpGte: ">=";
			case OpLt: "<";
			case OpLte: "<=";
			case OpShl: "<<";
			case OpShr: ">>";
			case OpUShr: ">>>";
			case OpAnd: "&";
			case OpOr: "|";
			case OpXor: "^";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpMod: "%";
			case _: return fail(null, "operator has no TypeScript lowering");
		}
	}

	function precedenceOf(op: Binop): Int {
		return switch(op) {
			case OpBoolOr: 1;
			case OpBoolAnd: 2;
			case OpOr: 3;
			case OpXor: 4;
			case OpAnd: 5;
			case OpEq | OpNotEq: 6;
			case OpLt | OpLte | OpGt | OpGte: 7;
			case OpShl | OpShr | OpUShr: 8;
			case OpAdd | OpSub: 9;
			case OpMult | OpDiv | OpMod: 10;
			case _: 0;
		}
	}

	function associative(op: Binop): Bool {
		return switch(op) {
			case OpOr | OpXor | OpAnd | OpBoolAnd | OpBoolOr | OpAdd | OpMult: true;
			case _: false;
		}
	}

	function isShift(op: Binop): Bool {
		return switch(op) {
			case OpShl | OpShr | OpUShr: true;
			case _: false;
		}
	}

	function isBitwiseLogical(op: Binop): Bool {
		return switch(op) {
			case OpOr | OpXor | OpAnd: true;
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

	function isBytes(e: TypedExpr): Bool {
		return switch(e.t) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
			case _: false;
		}
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

	/**
		The filter stage between typing and generation wraps nodes in
		TParenthesis, coercive TCast, and TMeta; structural matchers look
		through all three.
	**/
	function stripWrap(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripWrap(inner);
			case _: e;
		}
	}

	function stripMeta(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TMeta(_, inner): stripMeta(inner);
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
				case c: b.addChar(c);
			}
		}
		b.addChar('"'.code);
		return b.toString();
	}

	function escapeTemplate(s: String): String {
		final b = new StringBuf();
		for(i in 0...s.length) {
			switch(s.charCodeAt(i)) {
				case 92: b.add('\\\\');
				case 96: b.add('\\`');
				case 36: b.add('\\$');
				case c: b.addChar(c);
			}
		}
		return b.toString();
	}

	function indent(depth: Int): String {
		final b = new StringBuf();
		for(i in 0...depth) {
			b.add("  ");
		}
		return b.toString();
	}

	function fail(e: Null<TypedExpr>, message: String): Dynamic {
		final pos = e != null ? e.pos : Context.currentPos();
		Context.error("ts target: " + message, pos);
		return null;
	}
}
#end
