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

/**
	Statement and expression lowering from the Haxe typed AST to Rust.
**/
class RustExpr {
	final imports: RustImports;
	final types: RustType;
	final state: RustEmissionState;

	var isFallible: Bool = false;
	var countOverflowVariant: Null<String> = null;
	var errorTypeName: Null<String> = null;

	final subst: Map<Int, String> = [];
	final mutated: Map<Int, Bool> = [];
	final usedNames: Map<String, Bool> = [];
	final hiddenNames: Map<Int, String> = [];
	final rangeLoopVars: Map<Int, Bool> = [];
	final argTypes: Map<String, String> = [];
	var hiddenCounter: Int = 0;

	public function new(imports: RustImports, types: RustType, state: RustEmissionState) {
		this.imports = imports;
		this.types = types;
		this.state = state;
	}

	public function setArgType(name: String, typeName: String): Void {
		argTypes.set(name, typeName);
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
		this.countOverflowVariant = overflowVariant != null ? overflowVariant : state.overflowVariant;
		if(value && (this.errorTypeName == null || this.countOverflowVariant == null)) {
			if(this.errorTypeName == null) {
				Context.error("fallible operation requires an error enum, but none found in AST", Context.currentPos());
			}
			if(this.countOverflowVariant == null) {
				Context.error("capacity expression requires a count overflow error variant, but none found in AST", Context.currentPos());
			}
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

	// ------------------------------------------------------------------
	// Function bodies
	// ------------------------------------------------------------------

	var currentMethodName: Null<String> = null;

	public function functionBody(f: ClassFuncData): Array<String> {
		if(f.expr == null) {
			Context.error("function field has no body to lower", f.field.pos);
		}
		currentMethodName = f.field.name;
		scanLocals(f.expr);
		final lines = blockLines(statementsOf(f.expr), 2);
		return lines;
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
			case TVar(v, init) if(init != null):
				final kw = mutated.exists(v.id) ? "let mut" : "let";
				final name = RustImports.toSnakeCase(localName(v));
				return [indent(depth) + '$kw $name = ${expr(init)};'];
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
			case TReturn(ret):
				if(isFallible) {
					return [indent(depth) + "Ok(" + expr(ret) + ")"];
				}
				return [indent(depth) + expr(ret)];
			case TThrow(x):
				return [indent(depth) + "return Err(" + throwVariant(x) + ");"];
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

	function throwVariant(x: TypedExpr): String {
		final inner = stripWrap(x);
		switch(inner.expr) {
			case TNew(c, _, args) if(args.length == 1):
				return exceptionVariant(c.get(), args[0]);
			case _:
		}
		return expr(x);
	}

	function exceptionVariant(cls: ClassType, payloadArg: TypedExpr): String {
		final owner = state.payloadEnumOwners.get(state.exceptionPayloads.get(cls.module));
		final errType = owner != null ? owner : errorTypeName;
		if(errType == null) {
			Context.error("exception has no associated error enum in AST", cls.pos);
			return "";
		}
		final arg = stripWrap(payloadArg);
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

	function blockLines(stmts: Array<TypedExpr>, depth: Int): Array<String> {
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

		if(depth == 2 && isFallible) {
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
			case _:
				return null;
		}
	}

	function loopLines(loop, depth: Int): Array<String> {
		rangeLoopVars.set(loop.index.id, true);
		final name = RustImports.toSnakeCase(loop.index.name);
		final sliceSubj = sliceIterationSubject(loop);
		if(sliceSubj != null) {
			final itemVar = sliceItemVar(loop.body, loop.index, sliceSubj);
			if(itemVar != null) {
				final itemName = RustImports.toSnakeCase(itemVar.name);
				final remainingBody = loop.body.slice(1);
				final out = [
					indent(depth) + "for " + itemName + " in " + expr(sliceSubj) + " {"
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
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				out.push(indent(depth + 1) + arrName + ".push(" + expr(store.value) + ");");
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				out.push(indent(depth + 1) + arrName + ".push(" + expr(push.arg) + ");");
				continue;
			}
			for(l in stmtLines(s, depth + 1)) out.push(l);
		}
		out.push(indent(depth) + "}");
		return out;
	}

	function capacityExpr(bound: TypedExpr): String {
		if(errorTypeName == null || countOverflowVariant == null) {
			Context.error("cannot lower fallible capacity expression: missing error enum or overflow variant", bound.pos);
			return "0";
		}
		final errVariant = errorTypeName + "::" + countOverflowVariant;
		final inner = stripWrap(bound);
		switch(inner.expr) {
			case TConst(TInt(n)) if(n >= 0):
				return Std.string(n);
			case TField(subj, fa) if(fieldName(fa) == "length"):
				return expr(subj) + ".len()";
			case _:
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
		switch(e.expr) {
			case TConst(c):
				switch(c) {
					case TInt(v): return Std.string(v);
					case TFloat(f):
						final s = Std.string(f);
						return s.indexOf(".") >= 0 ? s : s + ".0";
					case TString(s): return quoteString(s);
					case TBool(b): return b ? "true" : "false";
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
				return "vec![" + [for(x in elems) expr(x)].join(", ") + "]";
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
			case _:
				return fail(e, "expression has no Rust lowering in the subset: " + Std.string(e.expr));
		}
	}

	function binop(e: TypedExpr, op: Binop, l: TypedExpr, r: TypedExpr): String {
		final fromBe = tryMatchFromBeBytes(e);
		if(fromBe != null) {
			return fromBe;
		}
		switch(op) {
			case OpAssign:
				return assignTarget(l) + " = " + expr(r);
			case OpAssignOp(inner):
				return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
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
				return "(" + operand(l, op, false) + " >> " + operand(r, op, true) + ")";
			case OpLt if(isZero(r)):
				return expr(l) + " > 2147483647";
			case OpSub:
				return operand(l, op, false) + " - " + operand(r, op, true);
			case _:
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
		}
	}

	function isZero(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(TInt(0)): true;
			case _: false;
		};
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
			case OpIncrement: return inner + " += 1";
			case OpDecrement: return inner + " -= 1";
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
				final errType = owner != null ? owner : en.name;
				imports.requireType(en.module, errType);
				return errType + "::" + ef.name;
			case FInstance(_, _, cf) | FAnon(cf):
				final name = cf.get().name;
				if(name == "length") {
					return expr(subj) + ".len()";
				}
				final snake = RustImports.toSnakeCase(name);
				return expr(subj) + "." + snake;
			case FDynamic(_):
				return fail(subj, "dynamic field access has no lowering");
			case FClosure(_):
				return fail(subj, "closure has no lowering");
		}
	}

	function staticRef(cls: ClassType, name: String): String {
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "String":
				return "String::" + RustImports.toSnakeCase(name);
			case _:
				imports.requireType(cls.module, cls.name);
				return cls.name + "::" + RustImports.toSnakeCase(name);
		}
	}

	function typeExpr(t: ModuleType): String {
		switch(t) {
			case TClassDecl(c):
				final cls = c.get();
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

	function call(fn: TypedExpr, args: Array<TypedExpr>): String {
		final renderedArgs = [for(a in args) expr(a)].join(", ");
		switch(fn.expr) {
			case TField(subj, FInstance(_, _, cf)):
				final name = cf.get().name;
				final snake = RustImports.toSnakeCase(name);
				if(name == "get" && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + "]";
				}
				if(name == "charCodeAt" && isString(stripCast(subj))) {
					return expr(subj) + ".as_bytes()[" + expr(args[0]) + "]";
				}
				if(name == "push") {
					return expr(subj) + ".push(" + renderedArgs + ")";
				}
				if(name == "join") {
					return expr(subj) + ".join(" + renderedArgs + ")";
				}
				if(name == "addByte") {
					return expr(subj) + ".add_byte(" + expr(args[0]) + ")";
				}
				if(name == "writeU16") {
					return expr(subj) + ".write_u16(" + expr(args[0]) + ")";
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
					return expr(subj) + ".write_ascii(" + expr(args[0]) + ")";
				}
				final isMethodFallible = isFallibleMethod(name);
				final q = (isFallible && isMethodFallible) ? "?" : "";
				return expr(subj) + "." + snake + "(" + renderedArgs + ")" + q;
			case TField(_, FStatic(c, cf)):
				final cls = c.get();
				final name = cf.get().name;
				final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
				if(cls.pack.length == 0 && cls.name == "String" && name == "fromCharCode") {
					return "char::from(" + expr(args[0]) + ").to_string()";
				}
				if(path == "haxe.io.FPHelper") {
					imports.requireType(cls.module, "FPHelper");
					return "FPHelper::" + RustImports.toSnakeCase(name) + "(" + renderedArgs + ")";
				}
				if(cls.pack.join(".") == "std" && cls.name == "Process" && name == "exit") {
					imports.require("std::process::exit");
					return "exit(" + renderedArgs + ")";
				}
				final isStaticFallible = isFallibleMethod(name);
				final q = (isFallible && isStaticFallible) ? "?" : "";
				return staticRef(cls, name) + "(" + renderedArgs + ")" + q;
			case TField(subj, FEnum(e, ef)):
				final en = e.get();
				final owner = state.payloadEnumOwners.get(en.module);
				final errType = owner != null ? owner : en.name;
				imports.requireType(en.module, errType);
				final efArgs = switch(ef.type) {
					case TFun(fargs, _): fargs;
					case _: [];
				};
				final parts = [];
				for(i in 0...args.length) {
					final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
					parts.push(argName + ": " + expr(args[i]));
				}
				return errType + "::" + ef.name + " { " + parts.join(", ") + " }";
			case TConst(TSuper):
				return "super(" + renderedArgs + ")";
			case _:
				return expr(fn) + "(" + renderedArgs + ")";
		}
	}

	function isFallibleMethod(name: String): Bool {
		return name == "readU16" || name == "readU32" || name == "readF64" || name == "readAscii"
			|| name == "ensureRemaining" || name == "decode" || name == "encode";
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final renderedArgs = [for(a in args) expr(a)].join(", ");
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
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
				return cls.name + "::new(" + renderedArgs + ")";
		}
	}

	function assignTarget(e: TypedExpr): String {
		switch(e.expr) {
			case TArray(arr, idx):
				return expr(arr) + "[" + expr(idx) + "]";
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
		final parts = [for(f in fields) RustImports.toSnakeCase(f.name) + ": " + expr(f.expr)];
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
						if(n == "readU16" || n == "readU32" || n == "readF64" || n == "readAscii"
							|| n == "writeU16" || n == "writeU32" || n == "writeF64" || n == "writeAscii"
							|| n == "addByte" || n == "push" || n == "finish") {
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
}
#end
