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
import ValueTypeSupport;

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
	  ReadOnlyArray returns records with read-only properties.
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

	/** Target-language aliases for Haxe's synthetic wrapper receivers. */
	final localAliases: Map<Int, String> = [];

	/** Fill arrays frozen at the return when decodeBoundary holds. */
	final frozenFill: Map<Int, Bool> = [];

	/** Names used by parameters and locals; generated names avoid them. */
	final usedNames: Map<String, Bool> = [];
	/** Locals backed by the FPHelper high/low boundary object. */
	final fpInt64Halves: Map<Int, Bool> = [];

	/** Catch variables in scope, keyed by TVar id (features/06). */
	final catchVars: Map<Int, Bool> = [];

	final hiddenNames: Map<Int, String> = [];
	var hiddenCounter: Int = 0;
	var hoistCounter: Int = 0;
	/** Fresh names for the trailing-unit reads of stdlib/08 checks. */
	var stringBufTailCounter: Int = 0;

	/** Function context used to distinguish a sanctioned coalescing site. */
	var currentClass: Null<ClassType> = null;
	var currentField: Null<String> = null;
	var currentLocalName: Null<String> = null;

	public function new(imports: TsImports, types: TsType) {
		this.imports = imports;
		this.types = types;
	}

	public function reserveName(name: String): Void {
		usedNames.set(name, true);
	}

	/** Gives a synthetic wrapper receiver its target-language parameter name. */
	public function bindLocalName(v: Null<TVar>, name: String): Void {
		if(v != null) {
			localAliases.set(v.id, name);
			reserveName(name);
		}
	}

	public function setDecodeBoundary(value: Bool): Void {
		decodeBoundary = value;
	}

	/** Expression entry for callers holding a bare typed expression. */
	public function expressionOf(e: TypedExpr): String {
		return expr(e);
	}

	/** Entry at statement scope for framework-initiated compiles. */
	public function topLevelStatements(e: TypedExpr): String {
		scanLocals(e);
		return blockLines(statementsOf(e), 0).join("\n");
	}

	public function rawExpression(e: TypedExpr): String {
		return expr(e);
	}

	function coalescingSiteFor(e: TypedExpr): Null<{parameter: String, defaultExpr: TypedExpr, valueExpr: TypedExpr}> {
		if(currentClass == null || currentField == null) return null;
		final site = DefaultArgExpander.coalescingSite(e);
		final value = currentLocalName != null
			? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, site == null ? "" : site.parameter)
			: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, site == null ? "" : site.parameter);
		if(site == null) {
			return null;
		}
		if(value == null && !DefaultArgExpander.isNormalizationSource(site.defaultExpr.pos)) return null;
		return site;
	}

	/** Renders a sanctioned default in the TypeScript parameter type context. */
	public function coalescingDefaultText(value: DefaultArgExpander.CoalescingDefaultValue, targetType: Type): String {
		return switch(value) {
			case CInt(v): Std.string(v);
			case CFloat(s): s;
			case CString(s): quoteString(s);
			case CBool(b): b ? "true" : "false";
			case CNull: "null";
			case CEmptyArray: "[]";
			case CEmptyMap: "new Map()";
			case CPositiveInfinity: "Infinity";
			case CNegativeInfinity: "-Infinity";
			case CEnum(enumRef, enumField):
				final en = enumRef.get();
				if(isValueEnum(en)) imports.value(en.module, en.name);
				isValueEnum(en) ? en.name + "." + enumField.name : "{ kind: \"" + enumField.name + "\" }";
			case CParameterRead(name): name;
			case CInstanceFieldRead(name): "this." + name;
			case CLocalRead(name): name;
			case CFieldAccess(CParameterRead(staticPath), ""): coalescingStaticFieldText(staticPath);
			case CFieldAccess(receiver, fieldName): coalescingDefaultText(receiver, targetType) + "." + fieldName;
			case CMethodCall(receiver, methodName, args):
				coalescingDefaultText(receiver, targetType) + "." + methodName + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CStaticCall(fullPath, args):
				coalescingStaticCallText(fullPath, args, targetType);
			case CConditional(c, t, f):
				"(" + coalescingDefaultText(c, targetType) + " ? " + coalescingDefaultText(t, targetType) + " : " + coalescingDefaultText(f, targetType) + ")";
			case CBinaryOp(op, left, right):
				coalescingDefaultText(left, targetType) + " " + opStr(op) + " " + coalescingDefaultText(right, targetType);
			case CConstructorCall(classPath, args):
				"new " + classPath.split(".").pop() + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
		};
	}

	function coalescingStaticCallText(path:String, args:Array<DefaultArgExpander.CoalescingDefaultValue>, targetType:Type):String {
		final rendered = [for(a in args) coalescingDefaultText(a, targetType)].join(", ");
		if(path == "std.SortedSet.builder") {
			final key = switch(Context.follow(DefaultArgExpander.withoutNull(targetType))) { case TInst(_, params) if(params.length > 0): params[0]; case _: null; };
			imports.runtime("SortedTable");
			return "SortedTable.setBuilder<" + types.of(key) + ">(" + sortedComparator(key, Context.currentPos()) + ")";
		}
		return path + "(" + rendered + ")";
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

	static function opStr(op:Binop):String {
		return switch(op) {
			case OpAdd: "+";
			case OpSub: "-";
			case OpMult: "*";
			case OpDiv: "/";
			case OpMod: "%";
			case OpEq: "===";
			case OpNotEq: "!==";
			case OpLt: "<";
			case OpLte: "<=";
			case OpGt: ">";
			case OpGte: ">=";
			case OpBoolAnd: "&&";
			case OpBoolOr: "||";
			case OpShl: "<<";
			case OpShr: ">>";
			case OpUShr: ">>>";
			case OpXor: "^";
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

		scanLocals(f.expr);
		return blockLines(statementsOf(f.expr), 2);
	}

	/** Body lowering shared by value-wrapper member functions. */
	public function valueTypeFunctionBody(cls: ClassType, f: ClassFuncData, receiverName: String = "value"): Array<String> {
		if(f.args.length > 0 && ValueTypeSupport.hasReceiver(f.field)) {
			bindLocalName(f.args[0].tvar, receiverName);
		}
		return functionBody(cls, f);
	}

	/**
		A Haxe abstract constructor assigns the synthetic `this` local and
		returns it. The representation is already the wrapper's value on this
		target, so only validation statements survive in the factory body.
	**/
	public function valueTypeConstructorBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) {
			Context.error("value type constructor has no body to lower", f.field.pos);
		}
		DefaultArgExpander.completeRootExpr(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
		if(f.args.length > 0) bindLocalName(f.args[0].tvar, f.args[0].name);
		scanLocals(f.expr);
		final out: Array<String> = [];
		for(stmt in statementsOf(f.expr)) {
			if(ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt)) continue;
			for(line in stmtLines(stmt, 1)) out.push(line);
		}
		return out;
	}

	/**
		Constructor body. TypeScript requires super() before any this
		access; Haxe allows field assignments before the super call, so
		the super call moves first. Subclasses of haxe.Exception also
		stamp this.name with the class name (stdlib/03).
	**/
	public function constructorBody(cls: ClassType, className: String, f: ClassFuncData, isException: Bool): Array<String> {
		if(f.expr == null) {
			Context.error("constructor has no body to lower", f.field.pos);
		}
		scanLocals(f.expr);
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
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
			case TVar(v, init) if(init != null && isTryRegion(init)):
				return tryBindingLines(v, init, depth);
			case TVar(v, init) if(init != null && isStringBufToStringCall(init)):
				return stringBufToStringBindingLines(v, stripWrap(init), depth);
			case TVar(v, init) if(init != null):
				final kw = mutated.exists(v.id) ? "let" : "const";
				final initText = switch(init.expr) {
					case TFunction(fn): functionLiteralNamed(v.name, fn);
					default: expr(init);
				};
				return [indent(depth) + '$kw ${localName(v)}${localTypeAnnotation(v, cast init)} = $initText;'];
			case TVar(v, init) if(init == null):
				return [indent(depth) + "let " + localName(v) + ": " + types.of(v.t) + ";"];
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
				return tryReturnLines(ret, depth);
			case TReturn(ret) if(ret != null && isStringBufToStringCall(ret)):
				return stringBufToStringReturnLines(stripWrap(ret), depth);
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
			case TTry(body, catches) if(catches.length == 1):
				return tryStatementLines(body, catches[0], depth);
			case TTry(_, _):
				return fail(e, "try region handles exactly one exception domain");
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
		// never occupies a name in the current block.
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
			if(EnumQueryExpander.aliasById(subject.id) != null) continue;
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
		// as a comma declaration; the block const form is not used.
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
		while are three sibling statements with no wrapping block.
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
			if(i + 1 < stmts.length) {
				final shortLoop = intervalShort(stmts[i], stmts[i + 1]);
				if(shortLoop != null) {
					final grouped: TypedExpr = {
						expr: TBlock([stmts[i], stmts[i + 1]]),
						pos: stmts[i].pos,
						t: stmts[i + 1].t
					};
					out.push(grouped);
					i += 2;
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
		final counter = switch(counterDecl.expr) {
			case TVar(v, start): {v: v, start: start};
			case _: return null;
		};
		final loop = switch(whileExpr.expr) {
			case TWhile(condition, body, _): {condition: condition, body: body};
			case _: return null;
		};
		final condition = stripWrap(loop.condition);
		final bound = switch(condition.expr) {
			case TBinop(OpLt, left, right):
				switch(stripWrap(left).expr) {
					case TLocal(value) if(value.id == counter.v.id): right;
					case _: return null;
				}
			case _: return null;
		};
		final bodyStmts = statementsOf(loop.body);
		if(bodyStmts.length == 0) return null;
		final capture = switch(bodyStmts[0].expr) {
			case TVar(value, init) if(init != null): {value: value, init: init};
			case _: return null;
		};
		return switch(stripWrap(capture.init).expr) {
			case TUnop(OpIncrement, true, subject):
				switch(stripWrap(subject).expr) {
					case TLocal(value) if(value.id == counter.v.id):
						{index: capture.value, start: counter.start, bound: bound, body: bodyStmts.slice(1)};
					case _: null;
				}
			case _: null;
		};
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
	// Counted fill (features/09) and read-only decode handling (features/18)
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
		final int64Expr = int64Expression(e);
		if(int64Expr != null) return int64Expr;
		final wrapperValue = ValueTypeSupport.syntheticValue(e);
		if(wrapperValue != null) return valueTypeSynthetic(e, wrapperValue);
		final query = enumQuery(e);
		if(query != null) return query;
		switch(e.expr) {
			case TTry(_, _):
				return fail(e, "try region lowers at statement, initializer, or return position");
			case TSwitch(_, _, _):
				return fail(e, "variant switch lowers at return position");
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
				final mapReceiver = mapBackingReceiver(arr);
				return mapReceiver == null ? expr(arr) + "[" + expr(idx) + "]!" : expr(mapReceiver) + ".get(" + expr(idx) + ")!";
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
				return functionLiteral(f);
			case TIf(c, t, f) if(f != null):
				final coalescing = coalescingSiteFor(e);
				if(coalescing != null) {
					return DefaultArgExpander.isNormalizationSource(coalescing.defaultExpr.pos)
						? expr(coalescing.valueExpr) + " ?? " + expr(coalescing.defaultExpr)
						: expr(coalescing.valueExpr);
				}
				return "(" + expr(c) + " ? " + expr(t) + " : " + expr(f) + ")";
			case _:
				return fail(e, "expression has no TypeScript lowering in the subset");
		}
	}

	function conditionalText(c:TypedExpr, t:TypedExpr, f:TypedExpr):String {
		final a = switch (t.expr) { case TIf(ic, it, iff): conditionalText(ic, it, iff); default: expr(t); };
		final b = switch (f.expr) { case TIf(ic, it, iff): conditionalText(ic, it, iff); default: expr(f); };
		return "(" + expr(c) + " ? " + a + " : " + b + ")";
	}
	/**
		Value-wrapper operations are represented by blocks which assign the
		underlying Haxe `this`. At a use site TypeScript calls the generated
		module function; inside that function the erased representation can
		use the native operator directly.
	**/
	function valueTypeSynthetic(wrapper: TypedExpr, value: TypedExpr): String {
		final abs = ValueTypeSupport.markedAbstractOfType(wrapper.t);
		if(abs == null) return expr(value);
		final localValues = valueTypeLocalValues(wrapper);
		final activeAbs = currentClass == null ? null : ValueTypeSupport.markedAbstractOfClass(currentClass);
		final activeField = activeAbs != null && currentField != null ? ValueTypeSupport.memberField(activeAbs, currentField) : null;
		final nativeOperator = activeAbs != null && activeField != null && ValueTypeSupport.sameAbstract(activeAbs, abs)
			&& currentField != null && ValueTypeSupport.operatorOf(abs, activeField) != null;
		return switch(stripWrap(value).expr) {
			case TBinop(op, left, right):
				final field = ValueTypeSupport.binaryOperatorField(abs, op);
				if(field == null) expr(value) else if(nativeOperator && field.name == currentField) {
					valueTypeOperand(left, localValues) + " " + symbolOf(op) + " " + valueTypeOperand(right, localValues);
				} else {
					imports.functionRef(abs.module, field.name, true) + "(" + valueTypeOperand(left, localValues) + ", " + valueTypeOperand(right, localValues) + ")";
				}
			case TUnop(op, _, subject):
				final field = ValueTypeSupport.unaryOperatorField(abs, op);
				if(field == null) expr(value) else if(nativeOperator && field.name == currentField) {
					"-" + valueTypeOperand(subject, localValues);
				} else {
					imports.functionRef(abs.module, field.name, true) + "(" + valueTypeOperand(subject, localValues) + ")";
				}
			case _: expr(value);
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

	function valueTypeOperand(value:TypedExpr, locals:Map<Int, TypedExpr>):String {
		switch(stripWrap(value).expr) {
			case TLocal(v) if(locals.exists(v.id)):
				return expr(locals.get(v.id));
			case _:
		}
		return expr(value);
	}

	function enumQuery(e:TypedExpr):Null<String> {
		switch(e.expr) {
			case TField(subj, fa):
				final name = switch(fa) { case FInstance(_, _, cf) | FAnon(cf): cf.get().name; case FDynamic(n): n; case _: ""; };
				final en = EnumQueryExpander.collectionEnum(subj);
				if(name == "length" && en != null) return Std.string(EnumQueryExpander.constructorCount(en));
			case TArray(subj, index):
				final en = EnumQueryExpander.collectionEnum(subj);
				if(en != null) { if(EnumQueryExpander.aliasEnum(subj) != null) return expr(subj) + "[" + expr(index) + "]!"; imports.value(en.module, EnumQueryExpander.upperSnake(en.name) + "_ALL"); return EnumQueryExpander.upperSnake(en.name) + "_ALL[" + expr(index) + "]!"; }
			case _:
		}
		final kind = EnumQueryExpander.markerKind(e);
		if(kind == null) return null;
		final en = EnumQueryExpander.enumOf(e);
		final args = EnumQueryExpander.callArgs(e);
		return switch(kind) {
			case QCollection: imports.value(en.module, EnumQueryExpander.upperSnake(en.name) + "_ALL"); EnumQueryExpander.upperSnake(en.name) + "_ALL";
			case QName: expr(args[0]) + ".kind";
			case QLookup:
				final fn = EnumQueryExpander.lowerFirst(en.name) + "OfName"; imports.value(en.module, fn); fn + "(" + expr(args[1]) + ")";
		};
	}

	function functionLiteral(f: TFunc): String {
		final params = [for(a in f.args) {
			final value = currentLocalName != null && currentClass != null && currentField != null
				? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, a.v.name)
				: null;
			final parameterType = value != null ? DefaultArgExpander.coalescingParameterType(value, a.v.t) : a.v.t;
			final defaultText = value != null ? " = " + coalescingDefaultText(value, a.v.t) : "";
			'${a.v.name}: ${types.of(parameterType)}$defaultText';
		}].join(", ");
		final ret = types.of(f.t);
		return '($params): $ret => {\n' + blockLines(statementsOf(f.expr), 2).join("\n") + '\n}';
	}

	function functionLiteralNamed(name: String, f: TFunc): String {
		final previous = currentLocalName;
		currentLocalName = name;
		final result = functionLiteral(f);
		currentLocalName = previous;
		return result;
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
				final map = mapAssignment(l);
				return map == null ? assignTarget(l) + " = " + expr(r) : expr(map.receiver) + ".set(" + expr(map.key) + ", " + expr(r) + ")";
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
			case OpNegBits: return "~" + wrapped;
			case OpNeg: return "-" + wrapped;
			case _: {
				final infos = Context.getPosInfos(e.pos);
				return fail(e, "unary operator has no lowering in the subset: " + Std.string(op) + " at " + infos.file + ":" + infos.min);
			}
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
					case "make" if(args.length == 2):
						"BigInt.asIntN(64, (BigInt(" + expr(args[0]) + ") << 32n) | BigInt.asUintN(32, BigInt(" + expr(args[1]) + ")))";
					case "ofInt" if(args.length == 1): "BigInt.asIntN(64, BigInt(" + expr(args[0]) + "))";
					case "getHigh" | "get_high" if(args.length == 1):
						if(isFpHelperInt64Halves(args[0])) expr(args[0]) + ".high" else "Number(BigInt.asIntN(32, " + expr(args[0]) + " >> 32n))";
					case "getLow" | "get_low" if(args.length == 1):
						if(isFpHelperInt64Halves(args[0])) expr(args[0]) + ".low" else "Number(BigInt.asIntN(32, " + expr(args[0]) + "))";
					case "add" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " + " + expr(args[1]) + ")";
					case "sub" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " - " + expr(args[1]) + ")";
					case "and" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " & " + expr(args[1]) + ")";
					case "or" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " | " + expr(args[1]) + ")";
					case "xor" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " ^ " + expr(args[1]) + ")";
					case "complement" if(args.length == 1): "BigInt.asIntN(64, ~" + expr(args[0]) + ")";
					case "shl" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " << BigInt(" + expr(args[1]) + "))";
					case "shr" if(args.length == 2): "BigInt.asIntN(64, " + expr(args[0]) + " >> BigInt(" + expr(args[1]) + "))";
					case "ushr" if(args.length == 2): "BigInt.asIntN(64, BigInt.asUintN(64, " + expr(args[0]) + ") >> BigInt(" + expr(args[1]) + "))";
					case "eq" if(args.length == 2): expr(args[0]) + " === " + expr(args[1]);
					case "neq" if(args.length == 2): expr(args[0]) + " !== " + expr(args[1]);
					case "lt" if(args.length == 2): expr(args[0]) + " < " + expr(args[1]);
					case "gt" if(args.length == 2): expr(args[0]) + " > " + expr(args[1]);
					case "lte" if(args.length == 2): expr(args[0]) + " <= " + expr(args[1]);
					case "gte" if(args.length == 2): expr(args[0]) + " >= " + expr(args[1]);
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
			case FEnum(en, ef):
				final enumDef = en.get();
				if(isValueEnum(enumDef)) imports.value(enumDef.module, enumDef.name);
				return isValueEnum(enumDef) ? enumDef.name + "." + ef.name : "{ kind: \"" + ef.name + "\" }";
			case FInstance(_, _, cf) | FAnon(cf):
				final name = cf.get().name;
				final target = stripCast(subj);
				if((name == "high" || name == "low") && isFpHelperInt64Halves(target)) {
					return expr(target) + "." + name;
				}
				switch(target.expr) {
					case TLocal(v) if(name == "length" && boundSubst.exists(v.id)):
						return boundSubst.get(v.id);
					case _:
				}
				if(isCatchMessageAccess(target, name)) {
					return expr(target) + ".message";
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
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) {
			final field = ValueTypeSupport.memberField(valueType, name);
			return field == null ? name : imports.functionRef(valueType.module, name, field.isPublic);
		}
		final markedField = findStaticField(cls, name);
		if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
			return imports.functionRef(cls.module, name, markedField.isPublic);
		}
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "String":
				return "String." + name;
			case "Math":
				if(name == "NaN") return "Number.NaN";
				if(name == "isNaN") return "Number.isNaN";
				if(name == "POSITIVE_INFINITY") return "Infinity";
				if(name == "NEGATIVE_INFINITY") return "-Infinity";
				return "Math." + name;
			case "Std":
				if(name == "int") return "Math.trunc";
				if(name == "string") return "String";
				if(name == "parseFloat") return "Number.parseFloat";
				if(name == "parseInt") return "Number.parseInt";
				return "Std." + name;
			case "haxe.io.FPHelper":
				// stdlib/05: the bit conversions live in the runtime module.
				imports.runtime(name);
				return name;
			case _ if(TsTestBinding.isTestExtern(cls)):
				imports.runtimeTest("Test");
				return "Test." + name;
			case "std.SortedMap":
				// The sorted resident owns the factory functions; the
				// extern's `builder` maps onto the map flavor.
				imports.runtime("SortedTable");
				return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
			case "std.SortedSet":
				imports.runtime("SortedTable");
				return "SortedTable." + (name == "builder" ? "setBuilder" : name);
			case "std.UStringRT":
				imports.runtime("UString");
				return "UString." + name;
			case "std.Graphemes":
				imports.runtime("Graphemes");
				return "Graphemes." + name;
			case _:
				if(TsTestBinding.isTestExtern(cls)) {
					imports.runtimeTest("Test");
					return "Test." + name;
				}
				if(cls.module == "std.SortedMap") {
					imports.runtime("SortedTable");
					return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
				}
				if(cls.module == "std.SortedSet") {
					imports.runtime("SortedTable");
					return "SortedTable." + (name == "builder" ? "setBuilder" : name);
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

	function findStaticField(cls: ClassType, name: String): Null<ClassField> {
		for(field in cls.statics.get()) {
			if(field.name == name) {
				return field;
			}
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
				if(TsTestBinding.isTestExtern(cls)) {
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
		if(target.isInterface) {
			Context.error("Std.isOfType interface checks require a statically typed implementor on the TypeScript target", args[1].pos);
			return "false";
		}
		return expr(args[0]) + " instanceof " + expr(args[1]);
	}

	function stdStringType(t: Type, value: String, inConcat: Bool, origin: TypedExpr, depth: Int = 0): String {
		return switch(Context.follow(t)) {
			case TInst(c, _) if(c.get().name == "String"): value;
			case TInst(c, [element]) if(c.get().name == "Array"):
				final index = depth == 0 ? "i" : "i" + depth;
				final item = stdStringType(element, value + "[" + index + "]!", true, origin, depth + 1);
				'(() => { let out = "["; const n = ${value}.length; for (let ${index} = 0; ${index} < n; ${index} += 1) { if (${index} > 0) { out += ", "; } out += ${item}; } out += "]"; return out; })()';
			case TInst(c, _) if(StaticFieldHelper.hasSelfConstructionStatic(c.get()) || c.get().meta.has(":dataClass")): value + ".toString()";
			case TAbstract(a, _) if(ValueTypeSupport.isMarkedAbstract(a.get())):
				final abs = a.get();
				final toString = ValueTypeSupport.memberField(abs, "toString");
				toString == null ? (inConcat ? value : "String(" + value + ")") : imports.functionRef(abs.module, "toString", toString.isPublic) + "(" + value + ")";
			case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool"):
				inConcat ? value : "String(" + value + ")";
			case TAbstract(a, params) if(a.get().module == "std.ReadOnlyArray"):
				stdStringType(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, inConcat, origin, depth);
			case TEnum(en, _) if(isParameterlessEnum(en.get())): value + ".kind";
			case TEnum(en, _) : payloadEnumString(en.get(), value, inConcat, origin);
			case _:
				Context.error("Std.string accepts scalars, enum values, records, and arrays of them only", origin.pos);
				null;
		};
	}

	function payloadEnumString(en: EnumType, value: String, inConcat: Bool, origin: TypedExpr): String {
		final fields = [for(ef in en.constructs) ef];
		fields.sort((a, b) -> Reflect.compare(a.index, b.index));
		var out = "";
		for(i in 0...fields.length) {
			final ef = fields[i];
			final args = switch(ef.type) { case TFun(a, _): a; case _: []; };
			var arm = '"${ef.name}"';
			if(args.length > 0) {
				var body = '"${ef.name}(';
				for(j in 0...args.length) body += (j == 0 ? "" : ' + ", ') + args[j].name + '=" + ' + stdStringType(args[j].t, "(" + value + " as " + ef.name + ")." + args[j].name, true, origin, 0);
				arm = "(" + body + ' + ")")';
			}
			out = i == 0 ? arm : value + '.kind === "${ef.name}" ? ${arm} : ${out}';
		}
		return out;
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
		final hex = valueText + ".toString(16).toUpperCase()";
		return digits == null ? hex : hex + ".padStart(" + expr(digits) + ", \"0\")";
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

	/** Routes calls on a marked abstract implementation to its erased API. */
	function valueTypeCall(fn: TypedExpr, args: Array<TypedExpr>): Null<String> {
		switch(stripWrap(fn).expr) {
			case TField(_, FStatic(c, cf)):
				final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
				if(abs == null) return null;
				final field = cf.get();
				if(field.name == "_new") {
					if(args.length == 0) return abs.name;
					if(ValueTypeSupport.constructorThrows(abs)) {
						final constructor = ValueTypeSupport.constructorName(abs);
						imports.functionRef(abs.module, constructor, true);
						return constructor + "(" + expr(args[0]) + ")";
					}
					return expr(args[0]);
				}
				return imports.functionRef(abs.module, field.name, field.isPublic) + "(" + [for(a in args) expr(a)].join(", ") + ")";
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
				if(abs == null) return null;
				final field = cf.get();
				return imports.functionRef(abs.module, field.name, field.isPublic) + "(" + ([expr(subj)].concat([for(a in args) expr(a)])).join(", ") + ")";
			case _:
		}
		return null;
	}

	function call(fn: TypedExpr, args: Array<TypedExpr>): String {
		final int64CallText = int64Call(fn, args);
		if(int64CallText != null) return int64CallText;
		final wrapperCall = valueTypeCall(fn, args);
		if(wrapperCall != null) return wrapperCall;
		switch(fn.expr) {
			case TField(_, FStatic(c, cf)) if(c.get().module == "haxe.io.Bytes" && cf.get().name == "alloc" && args.length == 1):
				return "new Uint8Array(" + expr(args[0]) + ")";
			case TField(_, FStatic(c, cf)) if(c.get().module == "Std" && cf.get().name == "string" && args.length == 1):
				return stdString(args[0], false);
			case TField(_, FStatic(c, cf)) if(c.get().module == "Std" && cf.get().name == "isOfType" && args.length == 2):
				return stdIsOfType(args);
			case TField(subj, FInstance(_, _, cf)) if(cf.get().name == "get_message" && args.length == 0):
				final target = stripCast(subj);
				switch(target.expr) {
					case TLocal(v) if(catchVars.exists(v.id)):
						// Property getter on a caught exception: the native
						// message field (features/06: display text).
						return localName(v) + ".message";
					case _:
				}
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final fName = cf.get().name;
				if(cls.pack.length == 0 && cls.name == "StringTools" && fName == "hex") {
					return stringToolsHex(args);
				}
				if(cls.pack.length == 0 && cls.name == "StringTools" && fName == "trim" && args.length == 1) {
					return expr(args[0]) + ".trim()";
				}
				if(cls.module == "Std" && (fName == "parseFloat" || fName == "parseInt") && args.length == 1) {
					final s = expr(args[0]);
					if(fName == "parseFloat") return "((s) => { let a = 0, z = s.length; while (a < z) { const c = s.charCodeAt(a); if (c === 32 || (c >= 9 && c <= 13)) { a++; } else { break; } } while (z > a) { const c = s.charCodeAt(z - 1); if (c === 32 || (c >= 9 && c <= 13)) { z--; } else { break; } } let i = a; const c0 = s.charCodeAt(i); if (c0 === 43 || c0 === 45) { i++; } let before = 0; while (i < z) { const c = s.charCodeAt(i); if (c >= 48 && c <= 57) { i++; before++; } else { break; } } let after = 0; if (i < z && s.charCodeAt(i) === 46) { i++; while (i < z) { const c = s.charCodeAt(i); if (c >= 48 && c <= 57) { i++; after++; } else { break; } } } let ok = before > 0 || after > 0; if (ok && i < z) { const e = s.charCodeAt(i); if (e === 101 || e === 69) { i++; const c1 = s.charCodeAt(i); if (c1 === 43 || c1 === 45) { i++; } let m = 0; while (i < z) { const c = s.charCodeAt(i); if (c >= 48 && c <= 57) { i++; m++; } else { break; } } ok = m > 0; } else { ok = false; } } return ok && i === z ? Number.parseFloat(s.substring(a, z)) : Number.NaN; })(" + s + ")";
					return "((s) => { let a = 0, z = s.length; while (a < z) { const c = s.charCodeAt(a); if (c === 32 || (c >= 9 && c <= 13)) { a++; } else { break; } } while (z > a) { const c = s.charCodeAt(z - 1); if (c === 32 || (c >= 9 && c <= 13)) { z--; } else { break; } } let i = a; const c0 = s.charCodeAt(i); if (c0 === 43 || c0 === 45) { i++; } let radix = 10; if (i + 1 < z && s.charCodeAt(i) === 48 && (s.charCodeAt(i + 1) === 120 || s.charCodeAt(i + 1) === 88)) { i += 2; radix = 16; } const st = i; while (i < z) { const c = s.charCodeAt(i); if ((c >= 48 && c <= 57) || (radix === 16 && ((c >= 97 && c <= 102) || (c >= 65 && c <= 70)))) { i++; } else { break; } } if (i === st || i !== z) { return null; } const n = Number.parseInt(s.substring(a, z), radix); if (n >= -2147483648 && n <= 2147483647) { return n; } return null; })(" + s + ")";
				}
				if(cls.module == "Math" && fName == "isNaN" && args.length == 1) return "Number.isNaN(" + expr(args[0]) + ")";
				if(cls.module == "Math" && fName == "isFinite" && args.length == 1) return "Number.isFinite(" + expr(args[0]) + ")";
				if(cls.module == "std.UStringPlatform") {
					// Cursor primitives of the resident UString walk, inlined
					// per call: a cursor is a UTF-16 unit index here, so end
					// is the unit length and codePointAt combines surrogate
					// pairs. Business code never reaches these; it calls
					// std.UString.
					switch(fName) {
						case "end":
							return expr(args[0]) + ".length";
						case "codeAt":
							return expr(args[0]) + ".codePointAt(" + expr(args[1]) + ")!";
						case "advance":
							return "(" + expr(args[1]) + " + (" + expr(args[0]) + ".codePointAt(" + expr(args[1]) + ")! > 0xffff ? 2 : 1))";
						case "substringBetween":
							return expr(args[0]) + ".substring(" + expr(args[1]) + ", " + expr(args[2]) + ")";
						case "fromCodePoint":
							return "String.fromCodePoint(" + expr(args[0]) + ")";
						case _:
					}
				}
				if(TsTestBinding.isTestPlatformExtern(cls.module)) {
					// Host edges of the resident runtime.TestCore, inlined
					// per call: raising is a throw, the running test id
					// lives in the Test host of this same test entry, and
					// plain numbers render through String. Business code
					// never reaches these; it calls test extern.
					if(!imports.selfResident) {
						Context.error("test platform extern is a resident runtime primitive; business code calls test extern", fn.pos);
					}
					switch(fName) {
						case "raise":
							return "throw new Error(" + expr(args[0]) + ")";
						case "currentTestId":
							return "Test.currentTestIdState()";
						case "intToString":
							return "String(" + expr(args[0]) + ")";
						case "floatToString":
							return "String(" + expr(args[0]) + ")";
						case _:
					}
				}
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
	final inlineMapCall = mapHasOwnPropertyCall(fn, args);
		if(inlineMapCall != null) {
			return inlineMapCall;
		}
		switch(fn.expr) {
			case TCast(inner, _):
				return call(inner, args);
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return expr(subj) + ".length";
			case TField(subj, FInstance(_, _, cf)):
				final name = cf.get().name;
				if(isStringSubject(subj)) {
					if(name == "toLowerCase") return expr(subj) + ".toLowerCase()";
					if(name == "toUpperCase") return expr(subj) + ".toUpperCase()";
				}
				if(isMapType(subj.t)) {
					if(name == "exists" && args.length == 1) return expr(subj) + ".has(" + expr(args[0]) + ")";
					if(name == "get" && args.length == 1) return expr(subj) + ".get(" + expr(args[0]) + ")";
					if(name == "set" && args.length == 2) return expr(subj) + ".set(" + expr(args[0]) + ", " + expr(args[1]) + ")";
				}
				if(isStringBuf(subj)) {
					// stdlib/08: the checks throw, and a throw is a
					// statement here, so the checked operations lower at
					// statement, binding, or return position only.
					if(name == "add") {
						return fail(subj, "string buffer add has no expression lowering: keep the mutation a statement (stdlib/08)");
					}
					if(name == "addChar") {
						return fail(subj, "string buffer addChar has no expression lowering: keep the mutation a statement (stdlib/08)");
					}
					if(name == "toString") {
						return fail(subj, "string buffer toString has no expression lowering: bind it to a local or return it (stdlib/08)");
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
				if(name == "set" && args.length == 2 && isBytes(stripCast(subj))) {
					return expr(subj) + "[" + expr(args[0]) + "] = " + expr(args[1]);
				}
				if(name == "blit" && args.length == 4 && isBytes(stripCast(subj))) {
					return expr(subj) + ".set(" + expr(args[1]) + ".subarray(" + expr(args[2]) + ", " + expr(args[2]) + " + " + expr(args[3]) + "), " + expr(args[0]) + ")";
				}
				if(name == "fill" && args.length == 3 && isBytes(stripCast(subj))) {
					return expr(subj) + ".fill(" + expr(args[2]) + ", " + expr(args[0]) + ", " + expr(args[0]) + " + " + expr(args[1]) + ")";
				}
				if(name == "sub" && args.length == 2 && isBytes(stripCast(subj))) {
					return expr(subj) + ".slice(" + expr(args[0]) + ", " + expr(args[0]) + " + " + expr(args[1]) + ")";
				}
				if(name == "substring" && isStringSubject(subj)) {
					// The haxe typer passes a synthesized null for an
					// omitted ?endIndex; String.prototype.substring
					// coerces that null to 0 and swaps the bounds, so
					// the null argument is dropped and the platform
					// one-argument overload carries the suffix call.
					final endOmitted = args.length < 2 || switch(stripWrap(args[1]).expr) {
						case TConst(TNull): true;
						case _: false;
					};
					if(endOmitted) {
						return expr(subj) + ".substring(" + expr(args[0]) + ")";
					}
				}
				if(name == "substr" && isStringSubject(subj)) {
					// The same synthesized null arrives for an omitted
					// ?len; String.prototype.substr types its length
					// parameter as number, and a null argument fails
					// strict typechecking, so the null is dropped and
					// the one-argument overload carries the suffix call
					// (features/08 ruling 8).
					final lenOmitted = args.length < 2 || switch(stripWrap(args[1]).expr) {
						case TConst(TNull): true;
						case _: false;
					};
					if(lenOmitted) {
						return expr(subj) + ".substr(" + expr(args[0]) + ")";
					}
				}
				if(name == "indexOf" && (isStringSubject(subj) || isArraySubject(subj)) && args.length == 2) {
					// The same synthesized null arrives for an omitted
					// ?pos, on String and on Array; both prototype
					// methods type the position parameter as number,
					// and a null argument fails strict typechecking, so
					// the null is dropped and the one-argument overload
					// searches from the start (features/08 ruling 8).
					switch(stripWrap(args[1]).expr) {
						case TConst(TNull):
							return expr(subj) + ".indexOf(" + expr(args[0]) + ")";
						case _:
					}
				}
				return expr(subj) + "." + name + "(" + rendered + ")";
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final fName = cf.get().name;
		
				if((cls.module == "std.SortedMap" || cls.pack.join(".") + "." + cls.name == "std.SortedMap") && fName == "builder") {
					// Explicit type arguments: the annotated Haxe local
					// does not reach the emitted declaration.
					return "SortedTable.mapBuilder<" + types.of(kTypeOf(fn)) + ", " + types.of(vTypeOf(fn)) + ">(" + sortedComparator(kTypeOf(fn), fn.pos) + ")";
				}
				if((cls.module == "std.SortedSet" || cls.pack.join(".") + "." + cls.name == "std.SortedSet") && fName == "builder") {
					return "SortedTable.setBuilder<" + types.of(kTypeOf(fn)) + ">(" + sortedComparator(kTypeOf(fn), fn.pos) + ")";
				}
				return staticRef(c.get(), cf.get().name) + "(" + rendered + ")";
			case TField(_, FEnum(en, ef)):
				return enumConstruct(en.get(), ef, args);
			case TConst(TSuper):
				return "super(" + rendered + ")";
			case _:
				return expr(fn) + "(" + rendered + ")";
		}
	}

	/** The key type argument of a sorted builder factory call. */
	function kTypeOf(fn: TypedExpr): Null<Type> {
		return switch(fn.t) {
			case TFun(_, TInst(_, params)) if(params.length > 0): params[0];
			case _: null;
		};
	}

	/** The value type argument of a sorted map builder factory call. */
	function vTypeOf(fn: TypedExpr): Null<Type> {
		return switch(fn.t) {
			case TFun(_, TInst(_, params)) if(params.length > 1): params[1];
			case _: null;
		};
	}

	/**
		The comparator a sorted builder binds at creation, per key domain
		(stdlib/07): integers take the resident comparator, strings
		compare with the platform operator (the ruled UTF-16 code-unit
		order), structures take the per-type generated comparison.
	**/
	function sortedComparator(kType: Null<Type>, pos: haxe.macro.Expr.Position): String {
		if(kType == null) {
			Context.error("sorted builder requires an explicit key type", pos);
		}
		imports.runtime("SortedTable");
		return switch(TsType.classifyKey(kType, pos)) {
			case IntKey: "SortedTable.compareInts";
			case StringKey: "SortedTable.compareStrings";
			case StructKey(def, _):
				final cmpName = "compare" + def.name;
				imports.value(def.module, cmpName);
				cmpName;
		};
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

	function enumConstruct(en: EnumType, ef: EnumField, args: Array<TypedExpr>): String {
		if(isValueEnum(en)) {
			imports.value(en.module, en.name);
			return en.name + "." + ef.name;
		}
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

	static function isValueEnum(en: EnumType): Bool {
		for(ef in en.constructs) switch(Context.follow(ef.type)) {
			case TFun(args, _) if(args.length > 0): return false;
			case _:
		}
		return true;
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final rendered = [for(a in args) expr(a)].join(", ");
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return '""';
			case "haxe.ds._Map.Map_Impl_":
				return "new Map()";
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

	function isMapImplementation(cls:ClassType): Bool {
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
				receiver == null ? null : expr(receiver) + ".has(" + expr(args[1]) + ")";
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

	/**
		Try regions lower as native try/catch with instanceof narrowing on
		the exception class (features/06). The non-matching arm rethrows the
		caught value unchanged.
	**/
	function isTryRegion(e: Null<TypedExpr>): Bool {
		if(e == null) return false;
		return switch(stripWrap(e).expr) {
			case TTry(_, catches): catches.length == 1;
			case _: false;
		};
	}

	function tryRegionParts(e: TypedExpr): Null<{body: TypedExpr, c: {v: TVar, expr: TypedExpr}}> {
		return switch(stripWrap(e).expr) {
			case TTry(body, catches) if(catches.length == 1): {body: body, c: catches[0]};
			case _: null;
		};
	}

	/** The emitted class name behind `instanceof`, with its import registered. */
	function exceptionClassOf(c: {v: TVar, expr: TypedExpr}): Null<String> {
		return switch(Context.follow(c.v.t)) {
			case TInst(cls, _):
				imports.value(cls.get().module, cls.get().name);
				cls.get().name;
			case _: null;
		};
	}

	/**
		Splits a region body or handler into its leading statements and its
		trailing value expression; control-flow tails carry no value.
	**/
	function blockValueLines(e: TypedExpr, depth: Int): {lines: Array<String>, value: Null<String>} {
		final stmts = statementsOf(e);
		var value: Null<String> = null;
		var body = stmts;
		if(stmts.length > 0) {
			final last = stmts[stmts.length - 1];
			switch(last.expr) {
				case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TBlock(_) | TBreak | TContinue | TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
				case _:
					value = expr(last);
					body = stmts.slice(0, stmts.length - 1);
			}
		}
		return {lines: blockLines(body, depth), value: value};
	}

	function catchHeaderLines(c: {v: TVar, expr: TypedExpr}, clsName: String, depth: Int): Array<String> {
		final name = localName(c.v);
		return [
			indent(depth) + "} catch (" + name + ") {",
			indent(depth + 1) + "if (" + name + " instanceof " + clsName + ") {"
		];
	}

	function catchFooterLines(c: {v: TVar, expr: TypedExpr}, depth: Int): Array<String> {
		final name = localName(c.v);
		return [
			indent(depth + 1) + "} else {",
			indent(depth + 2) + "throw " + name + ";",
			indent(depth + 1) + "}",
			indent(depth) + "}"
		];
	}

	/** Statement-position region: the handler runs as a block. */
	function tryStatementLines(body: TypedExpr, c: {v: TVar, expr: TypedExpr}, depth: Int): Array<String> {
		final clsName = exceptionClassOf(c);
		if(clsName == null) {
			return fail(c.expr, "try region catch type is not an exception class");
		}
		final out = [indent(depth) + "try {"];
		for(l in blockLines(statementsOf(body), depth + 1)) out.push(l);
		for(l in catchHeaderLines(c, clsName, depth)) out.push(l);
		catchVars.set(c.v.id, true);
		final handler = blockLines(statementsOf(c.expr), depth + 2);
		catchVars.remove(c.v.id);
		for(l in handler) out.push(l);
		for(l in catchFooterLines(c, depth)) out.push(l);
		return out;
	}

	/**
		Initializer-position region: the try statement produces no value, so
		the binding hoists to a `let` and both arms assign it (features/06).
	**/
	function tryBindingLines(v: TVar, region: TypedExpr, depth: Int): Array<String> {
		final parts = tryRegionParts(region);
		if(parts == null) {
			return fail(region, "not a try region");
		}
		final clsName = exceptionClassOf(parts.c);
		if(clsName == null) {
			return fail(parts.c.expr, "try region catch type is not an exception class");
		}
		final name = localName(v);
		final out = [indent(depth) + "let " + name + ";", indent(depth) + "try {"];
		final body = blockValueLines(parts.body, depth + 1);
		if(body.value == null) {
			return fail(region, "try region body has no value");
		}
		for(l in body.lines) out.push(l);
		out.push(indent(depth + 1) + name + " = " + body.value + ";");
		for(l in catchHeaderLines(parts.c, clsName, depth)) out.push(l);
		catchVars.set(parts.c.v.id, true);
		final handler = blockValueLines(parts.c.expr, depth + 2);
		catchVars.remove(parts.c.v.id);
		if(handler.value == null) {
			return fail(parts.c.expr, "try region handler has no value");
		}
		for(l in handler.lines) out.push(l);
		out.push(indent(depth + 2) + name + " = " + handler.value + ";");
		for(l in catchFooterLines(parts.c, depth)) out.push(l);
		return out;
	}

	/** Return-position region: both arms return inside the native statement. */
	function tryReturnLines(region: TypedExpr, depth: Int): Array<String> {
		final parts = tryRegionParts(region);
		if(parts == null) {
			return fail(region, "not a try region");
		}
		final clsName = exceptionClassOf(parts.c);
		if(clsName == null) {
			return fail(parts.c.expr, "try region catch type is not an exception class");
		}
		final out = [indent(depth) + "try {"];
		final body = blockValueLines(parts.body, depth + 1);
		if(body.value == null) {
			return fail(region, "try region body has no value");
		}
		for(l in body.lines) out.push(l);
		out.push(indent(depth + 1) + "return " + body.value + ";");
		for(l in catchHeaderLines(parts.c, clsName, depth)) out.push(l);
		catchVars.set(parts.c.v.id, true);
		final handler = blockValueLines(parts.c.expr, depth + 2);
		catchVars.remove(parts.c.v.id);
		if(handler.value == null) {
			return fail(parts.c.expr, "try region handler has no value");
		}
		for(l in handler.lines) out.push(l);
		out.push(indent(depth + 2) + "return " + handler.value + ";");
		for(l in catchFooterLines(parts.c, depth)) out.push(l);
		return out;
	}

	/**
		stdlib/08 string-buffer checks (TypeScript): every checked
		operation reads the trailing UTF-16 unit, and the fault constructs
		the compiled std.UStringException with the UnpairedSurrogate
		variant. A throw is a statement here, so the checked operations
		lower at statement, binding, or return position only.
	**/
	function stringBufMutationParts(fn: TypedExpr): Null<{name: String, subj: TypedExpr}> {
		return switch(fn.expr) {
			case TField(subj, FInstance(_, _, cf)) if(isStringBuf(subj)):
				final n = cf.get().name;
				n == "add" || n == "addChar" ? {name: n, subj: subj} : null;
			case _: null;
		};
	}

	function isStringBufToStringCall(e: Null<TypedExpr>): Bool {
		if(e == null) return false;
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

	function freshTailName(): String {
		stringBufTailCounter += 1;
		return stringBufTailCounter == 1 ? "tail" : "tail" + stringBufTailCounter;
	}

	/** The trailing-unit read every check opens with; NaN compares false on an empty buffer. */
	function stringBufTailLines(subj: TypedExpr, depth: Int): {name: String, lines: Array<String>} {
		imports.value("std.UStringException", "UStringException");
		final name = freshTailName();
		final buf = expr(subj);
		return {
			name: name,
			lines: [indent(depth) + "const " + name + " = " + buf + ".charCodeAt(" + buf + ".length - 1);"]
		};
	}

	function stringBufFaultThrow(depth: Int, unit: String): String {
		return indent(depth) + 'throw new UStringException({ kind: "UnpairedSurrogate", unit: ' + unit + " });";
	}

	function stringBufMutationLines(fn: TypedExpr, args: Array<TypedExpr>, depth: Int): Array<String> {
		final parts = stringBufMutationParts(fn);
		if(parts == null) {
			return [fail(fn, "not a string buffer mutation")];
		}
		final buf = expr(parts.subj);
		final tailRead = stringBufTailLines(parts.subj, depth);
		final lines = tailRead.lines;
		final tail = tailRead.name;
		if(parts.name == "add") {
			final part = expr(args[0]);
			lines.push(indent(depth) + "if (" + tail + " >= 55296 && " + tail + " <= 56319 && " + part + ".length > 0"
				+ " && !(" + part + ".charCodeAt(0) >= 56320 && " + part + ".charCodeAt(0) <= 57343)) {");
			lines.push(stringBufFaultThrow(depth + 1, tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + " += " + part + ";");
		} else {
			final u = expr(args[0]);
			lines.push(indent(depth) + "if (" + u + " >= 56320 && " + u + " <= 57343) {");
			lines.push(indent(depth + 1) + "if (!(" + tail + " >= 55296 && " + tail + " <= 56319)) {");
			lines.push(stringBufFaultThrow(depth + 2, u));
			lines.push(indent(depth + 1) + "}");
			lines.push(indent(depth) + "} else if (" + tail + " >= 55296 && " + tail + " <= 56319) {");
			lines.push(stringBufFaultThrow(depth + 1, tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + " += String.fromCharCode(" + u + ");");
		}
		return lines;
	}

	function stringBufToStringCheckLines(subj: TypedExpr, depth: Int): Array<String> {
		final tailRead = stringBufTailLines(subj, depth);
		final lines = tailRead.lines;
		final tail = tailRead.name;
		lines.push(indent(depth) + "if (" + tail + " >= 55296 && " + tail + " <= 56319) {");
		lines.push(stringBufFaultThrow(depth + 1, tail));
		lines.push(indent(depth) + "}");
		return lines;
	}

	function stringBufToStringBindingLines(v: TVar, call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		final kw = mutated.exists(v.id) ? "let" : "const";
		lines.push(indent(depth) + kw + " " + localName(v) + " = " + expr(subj) + ";");
		return lines;
	}

	function stringBufToStringReturnLines(call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		lines.push(indent(depth) + "return " + expr(subj) + ";");
		return lines;
	}

	/**
		Message accessor on a caught exception: the property getter reads as
		the native message field (features/06: messages are display text).
	**/
	function isCatchMessageAccess(subj: TypedExpr, name: String): Bool {
		if(name != "message" && name != "get_message") {
			return false;
		}
		return switch(stripWrap(subj).expr) {
			case TLocal(v): catchVars.exists(v.id);
			case _: false;
		};
	}

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
			for(idx in 0...stmts.length) {
				final s = stmts[idx];
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
						// A case body may carry statements before its value
						// expression (an argument check that throws, a
						// mutation); each renders before the branch value's
						// return, and the final expression is the value.
						if(idx == stmts.length - 1) {
							value = expr(s);
						} else {
							for(l in stmtLines(s, depth)) out.push(l);
						}
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
				case _:
					final stdArg = stdStringArg(leaf);
					b.add("${" + (stdArg == null ? expr(leaf) : stdString(stdArg, true)) + "}");
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
		if(localAliases.exists(v.id)) {
			return localAliases.get(v.id);
		}
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

	function isStringSubject(e: TypedExpr): Bool {
		return switch(Context.follow(stripCast(e).t)) {
			case TInst(c, _): c.get().name == "String";
			case _: false;
		}
	}

	/**
		Three initializer forms cannot carry their declared type through
		TypeScript inference: a bare null widens to the evolving any and
		loses the null-model typing of features/04, an empty array
		literal stays an implicit any[] whenever the local is read
		through a path the evolving-array analysis rejects, and an enum
		constructor literal widens its kind tag to string, so a later
		discriminated-union use rejects the local. Those declarations
		name the declared type instead, mirroring the declaration-naming
		rule the Swift target already carries (features/14).
	**/
	function localTypeAnnotation(v: TVar, init: TypedExpr): String {
		return switch(stripWrap(init).expr) {
			case TConst(TNull) | TField(_, FEnum(_, _)): ": " + types.of(v.t);
			case TArrayDecl(elements) if(elements.length == 0): ": " + types.of(v.t);
			case _: "";
		};
	}

	function isArraySubject(e: TypedExpr): Bool {
		return switch(Context.follow(stripCast(e).t)) {
			case TInst(c, _): c.get().name == "Array";
			case _: false;
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
