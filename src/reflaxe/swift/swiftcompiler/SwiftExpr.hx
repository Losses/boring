package swiftcompiler;

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
	Statement and expression lowering from the Haxe typed AST to Swift.
	Every lowering is named after the ruling that requires it and derives
	from the shapes the typer and the pipeline expander produce (counted
	loops arrive as two hidden TVar statements plus a TWhile; the loop
	variable is captured through a post-increment of the hidden counter).

	- features/09 IntervalLoopRecognition: the counted loop re-emits as
	  `for i in stride(from: a, to: b, by: 1)`. Stride reads both bounds
	  once and yields an empty range when the bound precedes the start,
	  so neither the length hoist nor the allocation clamp of the TS lane
	  has a Swift counterpart: `a..<b` would trap on a negative decoded
	  count, stride never does.
	- features/09 CountedFillLowering: a fresh `[T]()` filled by a
	  counted loop whose body only stores elements (indexed store or one
	  append) reserves the bound once and appends. Array value semantics
	  freeze a let-bound array structurally, so the decode freeze of the
	  TS lane has no Swift counterpart.
	- stdlib/03 enum lowering: variants become cases of an Equatable
	  enum; construct comparisons read as `==`; variant switches lower as
	  a switch statement over the cases.
	- stdlib/04 ConstantAsciiFold: writeAscii of an all-ASCII constant
	  of width 4 or 2 folds to writeU32/writeU16 of the packed
	  big-endian word.
	- stdlib/01: haxe.io.Bytes.get(i) lowers to an Int32-wrapped UInt8
	  array index read; haxe.io.FPHelper bit conversions lower to the
	  runtime helpers (stdlib/05).
	- features/06 plus the numbers ruling: a call that can throw takes
	  the `try` marker at its statement, and every try region closes with
	  a bare rethrow arm because typed catch patterns never exhaust;
	  Haxe `/` on two Int operands yields Float, so it widens to Double;
	  `>>>` reinterprets through the bit-pattern initializers because
	  `UInt32(Int32)` traps on a negative argument.
**/
class SwiftExpr {
	final imports: SwiftImports;
	final types: SwiftType;

	/** True while emitting a function whose return type is ReadOnlyArray. */
	var decodeBoundary: Bool = false;

	/** Enum-capture locals mapped to the payload expression they stand for. */
	final subst: Map<Int, String> = [];

	/** Locals reassigned after their declaration; emitted with var. */
	final mutated: Map<Int, Bool> = [];

	/** Names written in the scanned body; parameters surface by name only. */
	final mutatedNames: Map<String, Bool> = [];

	/**
		Locals whose initializer is optional while the declared type is
		plain: the pipeline expander types a get()-initialized bucket as
		the plain value, and Swift infers the optional from the
		initializer. Value uses of such locals unwrap.
	**/
	final optionalInferred: Map<Int, Bool> = [];

	/** Names used by parameters and locals; generated names avoid them. */
	final usedNames: Map<String, Bool> = [];
	/** Catch variables in scope, keyed by TVar id (features/06). */
	final catchVars: Map<Int, Bool> = [];

	final hiddenNames: Map<Int, String> = [];
	var hiddenCounter: Int = 0;
	/** Fresh names for the trailing-unit reads of stdlib/08 checks. */
	var stringBufTailCounter: Int = 0;

	/** Function context used to distinguish a sanctioned coalescing site. */
	var currentClass: Null<ClassType> = null;
	var currentField: Null<String> = null;
	var currentLocalName: Null<String> = null;

	public function new(imports: SwiftImports, types: SwiftType) {
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

	/** Renders a sanctioned default in Swift's native parameter context. */
	public function coalescingDefaultText(value: DefaultArgExpander.CoalescingDefaultValue, targetType: Type): String {
		return switch(value) {
			case CInt(v): Std.string(v);
			case CFloat(s): s;
			case CString(s): quoteString(s);
			case CBool(b): b ? "true" : "false";
			case CNull: "nil";
			case CEmptyArray: "[]";
			case CEmptyMap: "[:]";
			case CPositiveInfinity: FloatPrecision.isF32() ? "Float.infinity" : "Double.infinity";
			case CNegativeInfinity: FloatPrecision.isF32() ? "-Float.infinity" : "-Double.infinity";
			case CEnum(enumRef, enumField): types.of(Type.TEnum(enumRef, [])) + "." + SwiftDecl.lowerFirst(enumField.name);
			case CParameterRead(name): name;
			case CFieldAccess(CParameterRead(staticPath), ""): staticPath;
			case CFieldAccess(receiver, fieldName): coalescingDefaultText(receiver, targetType) + "." + fieldName;
			case CMethodCall(receiver, methodName, args):
				coalescingDefaultText(receiver, targetType) + "." + swiftMethodName(methodName) + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CStaticCall(fullPath, args):
				fullPath + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CConditional(c, t, f):
				"(" + coalescingDefaultText(c, targetType) + " ? " + coalescingDefaultText(t, targetType) + " : " + coalescingDefaultText(f, targetType) + ")";
			case CBinaryOp(op, left, right):
				coalescingDefaultText(left, targetType) + " " + opStr(op) + " " + coalescingDefaultText(right, targetType);
		};
	}

	static function swiftMethodName(name:String):String {
		return name == "toUpperCase" ? "uppercased" : name;
	}

	static function opStr(op:Binop):String {
		return switch(op) {
			case OpAdd: "+";
			case OpSub: "-";
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
		// Depth 2: one level under the member's own indentation.
		return blockLines(statementsOf(f.expr), 2);
	}

	/**
		Constructor body. Swift initializes stored properties before the
		super call, the reverse of the TypeScript requirement, so field
		assignments move ahead of it. A missing super call on an
		exception class initializes the base with the empty message.
	**/
	public function constructorBody(cls: ClassType, className: String, f: ClassFuncData, isException: Bool): Array<String> {
		if(f.expr == null) {
			Context.error("constructor has no body to lower", f.field.pos);
		}
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
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
		for(i in 0...stmts.length) {
			if(i == superIdx) {
				continue;
			}
			for(l in stmtLines(stmts[i], 2)) out.push(l);
		}
		if(superIdx >= 0) {
			for(l in stmtLines(stmts[superIdx], 2)) out.push(l);
		} else if(isException) {
			out.push(indent(2) + "super.init(message: \"\")");
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
				final kw = mutated.exists(v.id) ? "var" : "let";
				final coalescing = coalescingSiteFor(init);
				final tryKw = containsThrowingCall(init) ? "try " : "";
				// Five initializers cannot carry their type to Swift's
				// inference: an empty array literal, an integer
				// initializer (a bare literal infers the 64-bit Int), an
				// array literal of integer literals (the elements default
				// to the 64-bit Int, nesting included), a sorted-builder
				// factory (the comparator fixes only the key), and a bare
				// nil. The declaration names the type instead.
				// (features/14: Int is Int32 on this lane.)
				// On the f32 lane a Float-typed declaration names its type
				// too: a bare float initializer infers the default Double
				// width (feature spec 23).
				final coalescingValue = coalescing == null ? null : (currentLocalName != null
					? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, coalescing.parameter)
					: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, coalescing.parameter));
				final localType = coalescingValue != null ? DefaultArgExpander.coalescingLocalType(coalescingValue, v.t) : v.t;
				final annotation = isEmptyArrayDecl(init) || isIntLeafType(v.t) || isIntLiteralArrayDecl(init) || isBuilderCall(init) || isNullLeafType(v.t)
					|| coalescing != null || (FloatPrecision.isF32() && isFloatLeafType(v.t)) ? ": " + types.of(localType) : "";
				final initText = switch(init.expr) {
					case TFunction(fn): functionLiteralNamed(v.name, fn);
					default: expr(init);
				};
				return [indent(depth) + '$kw ${localName(v)}$annotation = $tryKw$initText'];
			case TVar(v, _):
				// A declaration without initializer: definite
				// initialization assigns it on every path before use.
				return [indent(depth) + "var " + localName(v) + ": " + types.of(v.t)];
			case TBlock(stmts):
				return blockLines(stmts, depth);
			case TIf(c, t, f):
				return ifLines(c, t, f, depth);
			case TWhile(c, b, true):
				final out = [indent(depth) + "while " + conditionText(c) + " {"];
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
				return [indent(depth) + "return"];
			case TReturn(ret):
				final inner = stripWrap(ret);
				switch(inner.expr) {
					case TSwitch(_, _, _):
						return switchReturn(inner, depth);
					case _:
						final tryKw = containsThrowingCall(ret) ? "try " : "";
						return [indent(depth) + "return " + tryKw + expr(ret)];
				}
			case TThrow(x):
				return [indent(depth) + "throw " + expr(x)];
			case TTry(body, catches) if(catches.length == 1):
				return tryStatementLines(body, catches[0], depth);
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
			case TBinop(OpAssign, l, r):
				final tryKw = containsThrowingCall(r) ? "try " : "";
				final map = mapAssignment(l);
				final target = map == null ? assignTarget(l) + " = " : expr(map.receiver) + "[" + expr(map.key) + "] = ";
				return [indent(depth) + target + tryKw + expr(r)];
			case TBinop(OpAssignOp(inner), l, r):
				final tryKw = containsThrowingCall(r) ? "try " : "";
				return [indent(depth) + assignTarget(l) + " " + symbolOf(inner) + "= " + tryKw + expr(r)];
			case _:
				final tryKw = containsThrowingCall(e) ? "try " : "";
				// A call whose result the source discards reads as an
				// explicit discard; Swift warns on a bare non-Void call
				// in statement position.
				final discard = isDiscardedCall(e) ? "_ = " : "";
				return [indent(depth) + discard + tryKw + expr(e)];
		}
	}

	function ifLines(c: TypedExpr, t: TypedExpr, f: Null<TypedExpr>, depth: Int): Array<String> {
		final out = [indent(depth) + "if " + conditionText(c) + " {"];
		for(l in blockLines(statementsOf(t), depth + 1)) out.push(l);
		if(f != null) {
			final elseStmts = statementsOf(f);
			if(elseStmts.length == 1) {
				switch(stripWrap(elseStmts[0]).expr) {
					case TIf(_, _, _):
						// A sole nested else-if chains onto the brace.
						final inner = stmtLines(elseStmts[0], depth);
						out.push(indent(depth) + "} else " + StringTools.ltrim(inner[0]));
						for(i in 1...inner.length) out.push(inner[i]);
						return out;
					case _:
				}
			}
			out.push(indent(depth) + "} else {");
			for(l in blockLines(elseStmts, depth + 1)) out.push(l);
		}
		out.push(indent(depth) + "}");
		return out;
	}

	/** A condition with its try marker, when the test itself can throw. */
	function conditionText(c: TypedExpr): String {
		return containsThrowingCall(c) ? "try " + expr(c) : expr(c);
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
						out.push({expr: TVar(v, rhsExpr), pos: stmts[i].pos, t: stmts[i].t});
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

	function loopLines(loop: {index: TVar, start: TypedExpr, bound: TypedExpr, body: Array<TypedExpr>}, depth: Int): Array<String> {
		// A body that never reads the loop variable discards the binding.
		var readsIndex = false;
		for(s in loop.body) {
			if(mentionsLocal(s, loop.index)) {
				readsIndex = true;
				break;
			}
		}
		final name = readsIndex ? localName(loop.index) : "_";
		final out = [
			indent(depth) + "for " + name + " in stride(from: " + expr(loop.start) + ", to: " + expr(loop.bound) + ", by: 1) {"
		];
		final gb = matchGroupByBody(loop.body);
		if(gb != null) {
			// GroupByBucketValueSemantics: Swift arrays are value types,
			// so the builder put stores a copy and the trailing push
			// would never reach it. The loop re-emits as get-or-empty,
			// append, put, mirroring the Rust restructure macros/03
			// records for the same reason.
			for(l in blockLines(gb.prefix, depth + 1)) out.push(l);
			out.push(indent(depth + 1) + "let " + localName(gb.entryVar) + " = " + expr(gb.entryInit));
			out.push(indent(depth + 1) + "var " + localName(gb.bucketVar) + " = " + expr(gb.getCall) + " ?? " + types.of(gb.bucketVar.t) + "()");
			out.push(indent(depth + 1) + localName(gb.bucketVar) + ".append(" + expr(gb.valArg) + ")");
			out.push(indent(depth + 1) + expr(gb.builderSubj) + ".put(" + expr(gb.keyArg) + ", " + localName(gb.bucketVar) + ")");
			out.push(indent(depth) + "}");
			return out;
		}
		for(l in blockLines(loop.body, depth + 1)) out.push(l);
		out.push(indent(depth) + "}");
		return out;
	}

	/**
		The expander's groupBy core (macros/03): an entry declaration, a
		bucket bound to the builder get, the miss branch that allocates
		and puts, and the push. Returns the pieces the restructured
		emission needs; anything else leaves the loop untouched.
	**/
	function matchGroupByBody(body: Array<TypedExpr>): Null<{
		prefix: Array<TypedExpr>,
		entryVar: TVar,
		entryInit: TypedExpr,
		builderSubj: TypedExpr,
		keyArg: TypedExpr,
		getCall: TypedExpr,
		bucketVar: TVar,
		valArg: TypedExpr
	}> {
		if(body.length < 2) {
			return null;
		}
		// The lambda body lands as one trailing TBlock of the four core
		// statements, or as the four statements themselves.
		final core: Array<TypedExpr> = switch(body[body.length - 1].expr) {
			case TBlock(s) if(s.length == 4): s;
			case _: body.length == 4 ? body : null;
		}
		if(core == null) {
			return null;
		}
		final prefix = core == body ? [] : body.slice(0, body.length - 1);
		final entry = switch(core[0].expr) {
			case TVar(v, init) if(init != null): {v: v, init: init};
			case _: null;
		}
		if(entry == null) {
			return null;
		}
		final bucket = switch(core[1].expr) {
			case TVar(v, init) if(init != null):
				switch(stripWrap(init).expr) {
					case TCall({expr: TField(subj, fa)}, args) if(fieldName(fa) == "get" && args.length == 1 && isSortedBuilderSubject(subj)):
						{v: v, getCall: init, builderSubj: subj, keyArg: args[0]};
					case _: null;
				}
			case _: null;
		}
		if(bucket == null) {
			return null;
		}
		final missIsBucketIf = switch(core[2].expr) {
			case TIf(cond, _, _): mentionsLocal(cond, bucket.v);
			case _: false;
		}
		if(!missIsBucketIf) {
			return null;
		}
		final push = switch(core[3].expr) {
			case TCall({expr: TField(subj, fa)}, args) if(fieldName(fa) == "push" && args.length == 1):
				switch(stripWrap(subj).expr) {
					case TLocal(v) if(v.id == bucket.v.id): args[0];
					case _: null;
				}
			case _: null;
		}
		if(push == null) {
			return null;
		}
		return {
			prefix: prefix,
			entryVar: entry.v,
			entryInit: entry.init,
			builderSubj: bucket.builderSubj,
			keyArg: bucket.keyArg,
			getCall: bucket.getCall,
			bucketVar: bucket.v,
			valArg: push
		};
	}

	/** Whether a subject expression is a sorted-table builder instance. */
	function isSortedBuilderSubject(subj: TypedExpr): Bool {
		return switch(Context.follow(subj.t)) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "std" && StringTools.startsWith(cls.name, "Sorted");
			case _: false;
		};
	}

	// ------------------------------------------------------------------
	// Counted fill (features/09)
	// ------------------------------------------------------------------

	/**
		CountedFillLowering: `TVar arr = new Array<T>()` immediately
		followed by a counted loop whose only use of arr is storing one
		element per iteration (an indexed store at the loop index, or a
		single push) reserves the bound once and appends per iteration.
	**/
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
		// The stores render as appends, so the loop variable survives
		// only inside the interleaved non-store statements and the
		// stored values.
		var readsIndex = false;
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			final push = pushOf(s);
			if(store != null) {
				if(mentionsLocal(store.value, loop.index)) readsIndex = true;
			} else if(push != null) {
				if(mentionsLocal(push.arg, loop.index)) readsIndex = true;
			} else if(mentionsLocal(s, loop.index)) {
				readsIndex = true;
			}
			if(readsIndex) {
				break;
			}
		}
		final out: Array<String> = [];
		out.push(indent(depth) + "var " + arrName + " = [" + types.of(alloc.elem) + "]()");
		out.push(indent(depth) + arrName + ".reserveCapacity(Int(max(" + expr(loop.bound) + ", 0)))");
		out.push(indent(depth) + "for " + (readsIndex ? localName(loop.index) : "_") + " in stride(from: " + expr(loop.start) + ", to: " + expr(loop.bound) + ", by: 1) {");
		final nonStores: Array<TypedExpr> = [];
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + ".append(" + expr(store.value) + ")");
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + ".append(" + expr(push.arg) + ")");
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
					case TString(s):
						// The resident ABI carries strings as unit arrays
						// (targets/swift.md); business modules keep the
						// native literal.
						return types.resident ? "Array(" + quoteString(s) + ".utf16)" : quoteString(s);
					case TBool(b): return b ? "true" : "false";
					case TNull: return "nil";
					case TThis: return "self";
					case TSuper: return "super";
					case _: return fail(e, "constant has no Swift lowering");
				}
			case TLocal(v):
				if(subst.exists(v.id)) {
					return subst.get(v.id);
				}
				return localName(v);
			case TArray(arr, idx):
				final mapReceiver = mapBackingReceiver(arr);
				final read = mapReceiver == null ? expr(arr) + "[Int(" + expr(idx) + ")]" : expr(mapReceiver) + "[" + expr(idx) + "]";
				// haxe.io.Bytes reads carry UInt8 elements; the Haxe
				// access widens to Int.
				return mapReceiver == null && isBytesType(arr) ? "Int32(" + read + ")" : read;
			case TBinop(op, l, r):
				return binop(e, op, l, r);
			case TUnop(op, post, subj):
				return unop(e, op, post, subj);
			case TField(subj, fa):
				return field(subj, fa);
			case TTypeExpr(t):
				return typeExpr(t);
			case TParenthesis(inner):
				return expr(inner);
			case TObjectDecl(fields):
				return objectLiteral(e, fields);
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
			case TEnumParameter(_, _, _):
				return fail(e, "enum payload only lowers inside a variant switch arm");
			case TEnumIndex(_):
				return fail(e, "enum index only lowers inside a variant switch");
			case TFunction(f):
				return functionLiteral(f);
			case TIf(c, t, f) if(f != null):
				final coalescing = coalescingSiteFor(e);
				if(coalescing != null) {
					if(currentLocalName != null && currentClass != null && currentField != null) {
						final value = DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, coalescing.parameter);
						if(value != null) return expr(coalescing.valueExpr) + " ?? " + coalescingDefaultText(value, coalescing.valueExpr.t);
					}
					return expr(coalescing.valueExpr);
				}
				final optional = optionalIf(c, t, f);
				if(optional != null) return optional;
				return "(" + expr(c) + " ? " + expr(t) + " : " + expr(f) + ")";
			case _:
				return fail(e, "expression has no Swift lowering in the subset");
		}
	}

	function optionalIf(c: TypedExpr, ifTrue: TypedExpr, ifFalse: TypedExpr): Null<String> {
		var value: Null<TVar> = null;
		switch(stripWrap(c).expr) {
			case TBinop(OpEq, left, right) | TBinop(OpNotEq, left, right):
				if(isNullExpr(right)) {
					switch(stripWrap(left).expr) {
						case TLocal(v): value = v;
						case _:
					}
				} else if(isNullExpr(left)) {
					switch(stripWrap(right).expr) {
						case TLocal(v): value = v;
						case _:
					}
				}
			case _:
		}
		if(value == null) {
			return null;
		}
		final trueLocal = switch(stripWrap(ifTrue).expr) {
			case TLocal(v) if(v.id == value.id): true;
			case _: false;
		};
		final falseLocal = switch(stripWrap(ifFalse).expr) {
			case TLocal(v) if(v.id == value.id): true;
			case _: false;
		};
		if(trueLocal == falseLocal) {
			return null;
		}
		final fallback = trueLocal ? ifFalse : ifTrue;
		return expr(valueExpr(value)) + " ?? " + expr(fallback);
	}

	function valueExpr(v: TVar): TypedExpr {
		return {t: v.t, pos: Context.currentPos(), expr: TLocal(v)};
	}

	function enumQuery(e:TypedExpr):Null<String> {
		switch(e.expr) {
			case TField(subj, fa): final name = switch(fa) { case FInstance(_, _, cf) | FAnon(cf): cf.get().name; case FDynamic(n): n; case _: ""; }; final en = EnumQueryExpander.collectionEnum(subj); if(name == "length" && en != null) return Std.string(EnumQueryExpander.constructorCount(en));
			case TArray(subj, index): final en = EnumQueryExpander.collectionEnum(subj); if(en != null) { if(EnumQueryExpander.aliasEnum(subj) != null) return expr(subj) + "[Int(" + expr(index) + ")]"; imports.type(en.module, en.name); return en.name + ".allCases[Int(" + expr(index) + ")]"; }
			case _:
		}
		final kind = EnumQueryExpander.markerKind(e); if(kind == null) return null; final en = EnumQueryExpander.enumOf(e); final args = EnumQueryExpander.callArgs(e); imports.type(en.module, en.name);
		return switch(kind) { case QCollection: en.name + ".allCases"; case QName: expr(args[0]) + ".rawValue"; case QLookup: en.name + "(rawValue: " + expr(args[1]) + ")"; };
	}

	function functionLiteral(f: TFunc): String {
		final params = [for(a in f.args) a.v.name + ": " + types.of(a.v.t)].join(", ");
		// TFunc.t is the declared return type of the literal.
		final ret = types.of(f.t);
		final bodyStmts = statementsOf(f.expr);
		if(bodyStmts.length == 1) {
			switch(bodyStmts[0].expr) {
				case TReturn(r) if(r != null):
					return "{ (" + params + ") -> " + ret + " in " + expr(r) + " }";
				case _:
			}
		}
		return "{ (" + params + ") -> " + ret + " in\n" + blockLines(bodyStmts, 1).join("\n") + "\n}";
	}

	function functionLiteralNamed(name: String, f: TFunc): String {
		final previous = currentLocalName;
		currentLocalName = name;
		final result = functionLiteral(f);
		currentLocalName = previous;
		return result;
	}

	function binop(e: TypedExpr, op: Binop, l: TypedExpr, r: TypedExpr): String {
		switch(op) {
			case OpAssign:
				final map = mapAssignment(l);
			return map == null ? assignTarget(l) + " = " + expr(r) : expr(map.receiver) + "[" + expr(map.key) + "] = " + expr(r);
			case OpAssignOp(inner):
				return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
			case OpAdd:
				if(isStringTyped(e) && !types.resident) {
					return templateLiteral(l, r);
				}
				return operand(l, op, false) + " + " + operand(r, op, true);
			case OpUShr:
				// `>>>` reinterprets the bits: UInt32(Int32) traps on a
				// negative argument, so both sides cross through the
				// bit-pattern initializers (numbers ruling).
				return "Int32(bitPattern: UInt32(bitPattern: " + expr(l) + ") >> UInt32(bitPattern: " + expr(r) + "))";
			case OpDiv:
				// Haxe `/` on two Int operands yields Float; Swift `/` on
				// Int32 stays integral, so the operands widen first. The
				// widening target is the module real (feature spec 23).
				if(isIntTyped(l) && isIntTyped(r)) {
					final right = switch(stripWrap(r).expr) {
						case TConst(TInt(n)): Std.string(n);
						case _: realType() + "(" + expr(r) + ")";
					};
					return realType() + "(" + expr(l) + ") / " + right;
				}
				return floatAware(operand(l, op, false), l) + " / " + floatAware(operand(r, op, true), r);
			case OpEq | OpNotEq:
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
			case _:
				// Haxe mixes Int into Float arithmetic and comparison
				// with promotion; Swift has no implicit conversion, so
				// the Int side widens when the other side is Float.
				if((isFloatTyped(l) || isFloatTyped(r)) && (isFloatTyped(l) != isFloatTyped(r))) {
					return floatAware(operand(l, op, false), l) + " " + symbolOf(op) + " " + floatAware(operand(r, op, true), r);
				}
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
		}
	}

	/** The module real's Swift name; Int sides of Float operations widen to it. */
	function realType(): String {
		return FloatPrecision.isF32() ? "Float" : "Double";
	}

	/** The operand text with an Int side of a Float operation widened. */
	function floatAware(text: String, side: TypedExpr): String {
		if(!isIntTyped(side)) {
			return text;
		}
		return switch(stripWrap(side).expr) {
			// A bare literal converts in context once wrapped.
			case TConst(TInt(n)): realType() + "(" + n + ")";
			case _: realType() + "(" + text + ")";
		};
	}

	function isFloatTyped(e: TypedExpr): Bool {
		return switch(Context.follow(e.t)) {
			case TAbstract(a, _): a.get().name == "Float";
			case TLazy(f): switch(f()) {
				case TAbstract(a, _): a.get().name == "Float";
				case _: false;
			};
			case _: false;
		};
	}

	/**
		Parenthesization under Swift's own precedence table: a child
		below the parent's tier wraps, and an equal-tier right child
		wraps unless the same associative operator chains. Bitwise `|`
		and `^` share the additive tier and `&` the multiplicative tier,
		so mixed operators on one tier always wrap on the right.
	**/
	function operand(e: TypedExpr, parent: Binop, isRight: Bool): String {
		final rendered = expr(e);
		switch(stripWrap(e).expr) {
			case TBinop(op, _, _):
				final cp = precedenceOf(op);
				final pp = precedenceOf(parent);
				var parens = cp < pp;
				if(cp == pp && isRight) {
					parens = !(op == parent && associative(op));
				}
				return parens ? "(" + rendered + ")" : rendered;
			case _:
				return rendered;
		}
	}

	function unop(e: TypedExpr, op: Unop, post: Bool, subj: TypedExpr): String {
		final inner = expr(subj);
		final wrapped = switch(stripWrap(subj).expr) {
			case TBinop(_, _, _): "(" + inner + ")";
			case _: inner;
		}
		switch(op) {
			case OpNot: return "!" + wrapped;
			case OpNeg: return "-" + wrapped;
			case _:
				{
					final infos = Context.getPosInfos(e.pos);
					return fail(e, "unary operator has no lowering in the subset: " + Std.string(op) + " at " + infos.file + ":" + infos.min);
				}
		}
	}

	function field(subj: TypedExpr, fa: FieldAccess): String {
		switch(fa) {
			case FStatic(c, cf):
				return staticRef(c.get(), cf.get().name);
			case FEnum(en, ef):
				// A construct without payload in value position; the
				// qualified name carries the type context.
				final enumDef = en.get();
				imports.type(enumDef.module, enumDef.name);
				return enumDef.name + "." + SwiftDecl.lowerFirst(ef.name);
			case FInstance(_, _, cf) | FAnon(cf):
				final name = cf.get().name;
				final target = stripCast(subj);
				if(isCatchMessageAccess(target, name)) {
					return expr(target) + ".message";
				}
				if(name == "length") {
					if(isStringBuf(subj)) {
						return "Int32(" + receiverText(subj) + ".count)";
					}
					if(isStringSubject(subj) && !types.resident) {
						return "Int32(" + receiverText(subj) + ".utf16.count)";
					}
					return "Int32(" + receiverText(subj) + ".count)";
				}
				// Haxe flows Null<T> into T and smart-casts after the nil
				// guard; a field read through the optional force-unwraps
				// here.
				return receiverText(subj) + "." + name;
			case FDynamic(name):
				if((name == "length" || name == "get_length") && isStringBuf(subj)) {
					return "Int32(" + expr(subj) + ".count)";
				}
				return fail(subj, "dynamic field access has no lowering: " + name);
			case FClosure(_):
				return fail(subj, "function value has no lowering (V08)");
		}
	}

	function staticRef(cls: ClassType, name: String): String {
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		final module = cls.module != "" ? cls.module : path;
		switch(module) {
			case "Math":
				// The stdlib members map onto the Swift standard library:
				// no Foundation import runs for arithmetic. The f32 lane
				// reads every member from the Float family (feature
				// spec 23).
				if(FloatPrecision.isF32()) {
					if(name == "NaN") return "Float.nan";
					if(name == "POSITIVE_INFINITY") return "Float.infinity";
					if(name == "NEGATIVE_INFINITY") return "-Float.infinity";
				}
				if(name == "NaN") return "Double.nan";
				if(name == "POSITIVE_INFINITY") return "Double.infinity";
				if(name == "NEGATIVE_INFINITY") return "-Double.infinity";
				if(name == "abs" || name == "max" || name == "min") return name;
				return fail(null, "Math." + name + " has no direct Swift lowering; the call site lowers it");
			case "String":
				if(name == "fromCharCode") {
					return fail(null, "String.fromCharCode lowers at its call site");
				}
				return "String." + name;
			case "Std":
				if(name == "int" || name == "string") {
					return fail(null, "Std." + name + " lowers at its call site");
				}
				return "Std." + name;
			case "haxe.io.FPHelper":
				// stdlib/05: the bit conversions live in the runtime module.
				// The f32 lane swaps the two value-edge calls to the
				// binary32 variants; the 8-byte wire layout keeps its f64
				// shape on both lanes (feature spec 23).
				if(FloatPrecision.isF32()) {
					if(name == "i64ToDouble") {
						imports.runtime("i64ToF32");
						return "i64ToF32";
					}
					if(name == "doubleToI64") {
						imports.runtime("f32ToI64");
						return "f32ToI64";
					}
				}
				imports.runtime(name);
				return name;
			case "std.Test" | "std.__test_shim":
				imports.runtimeTest("Test");
				return "Test." + name;
			case "std.UStringRT":
				imports.runtime("UString");
				return "UString." + name;
			case "std.Graphemes":
				imports.runtime("Graphemes");
				return "Graphemes." + name;
			case "std.SortedMap":
				// The sorted resident owns the factory functions; the
				// extern's `builder` maps onto the map flavor.
				imports.runtime("SortedTable");
				return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
			case "std.SortedSet":
				imports.runtime("SortedTable");
				return "SortedTable." + (name == "builder" ? "setBuilder" : name);
			case _:
				imports.value(module, cls.name);
				return cls.name + "." + name;
		}
	}

	function typeExpr(t: ModuleType): String {
		switch(t) {
			case TClassDecl(c):
				final cls = c.get();
				if(cls.module == "std.Test" || (cls.pack.join(".") == "std" && (cls.name == "Test" || cls.name == "__test_shim"))) {
					imports.runtimeTest("Test");
					return "Test";
				}
				imports.value(cls.module, cls.name);
				return cls.name;
			case TEnumDecl(en):
				final enumDef = en.get();
				imports.value(enumDef.module, enumDef.name);
				return enumDef.name;
			case _:
				Context.error("type expression has no value lowering", Context.currentPos());
				return null;
		}
	}

	/**
		Call arguments unwrap optionals when the parameter demands a plain
		value: Haxe flows Null<T> into T implicitly (a null reaching the
		callee traps there), while Swift needs the explicit unwrap.
		Optional parameters and untyped parameters keep the argument as
		rendered.
	**/
	function argTexts(fn: TypedExpr, args: Array<TypedExpr>): Array<String> {
		final paramTypes: Array<Null<Type>> = switch(fn.expr) {
			case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
				switch(cf.get().type) {
					case TFun(fargs, _): [for(a in fargs) a.t];
					case _: [for(_ in args) null];
				}
			case TLocal(_):
				switch(Context.follow(fn.t)) {
					case TFun(fargs, _): [for(a in fargs) a.t];
					case _: [for(_ in args) null];
				}
			case _:
				[for(_ in args) null];
		};
		final rendered = [
			for(i in 0...args.length) {
				final a = args[i];
				final pt = i < paramTypes.length ? paramTypes[i] : null;
				final demandsValue = pt != null && !isNullLeafType(pt);
				demandsValue && optionalValued(a) ? expr(a) + "!" : expr(a);
			}
		];
		switch(fn.expr) {
			case TLocal(v) if(currentClass != null && currentField != null):
				for(i in args.length...paramTypes.length) {
					if(DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, v.name, switch(Context.follow(fn.t)) {
						case TFun(values, _): values[i].name;
						case _: "";
					}) != null) {
						rendered.push("nil");
					}
				}
			default:
		}
		return rendered;
	}

	/** A method receiver unwraps when the receiver expression is optional. */
	function receiverText(subj: TypedExpr): String {
		if(!optionalValued(subj)) {
			return expr(subj);
		}
		final base = expr(subj);
		return switch(stripWrap(subj).expr) {
			case TLocal(_): base + "!";
			case _: "(" + base + ")!";
		};
	}


	/** Whether a value-position expression carries an optional at runtime. */
	function optionalValued(e: TypedExpr): Bool {
		if(isNullLeafType(e.t)) {
			return true;
		}
		return switch(stripWrap(e).expr) {
			case TLocal(v): optionalInferred.exists(v.id);
			case _: false;
		};
	}

	function stdString(arg: TypedExpr, inConcat: Bool): String {
		return stdStringType(arg.t, expr(arg), inConcat, arg);
	}

	function stdStringType(t: Type, value: String, inConcat: Bool, origin: TypedExpr, depth: Int = 0): String {
		return switch(Context.follow(t)) {
			case TInst(c, _) if(c.get().name == "String"): value;
			case TInst(c, [element]) if(c.get().name == "Array"):
				final index = depth == 0 ? "i" : "i" + depth;
				final item = stdStringType(element, value + "[" + index + "]", true, origin, depth + 1);
				'{ () -> String in var out = "["; let n = ${value}.count; var ${index} = 0; while ${index} < n { if ${index} > 0 { out += ", "; }; out += ${item}; ${index} += 1; }; out += "]"; return out }()';
			case TInst(c, _) if(c.get().meta.has(":dataClass")): value + ".toString()";
			case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool"): depth > 0 ? "\"\\(" + value + ")\"" : (inConcat ? value : "String(" + value + ")");
			case TAbstract(a, params) if(a.get().module == "std.ReadOnlyArray"):
				stdStringType(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, inConcat, origin, depth);
			case TEnum(en, _) if(isParameterlessEnum(en.get())): value + ".rawValue";
			case _:
				Context.error("Std.string accepts scalars, parameterless enum values, and arrays of them only", origin.pos);
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
		final valueText = expr(value);
		final hex = "String(" + valueText + ", radix: 16, uppercase: true)";
		if(digits == null) {
			return hex;
		}
		final digitsText = "Int(" + expr(digits) + ")";
		return "{ let s = " + hex + "; return s.count < " + digitsText + " ? String(repeating: \"0\", count: " + digitsText + " - s.count) + s : s }()";
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

	function call(fn: TypedExpr, args: Array<TypedExpr>): String {
		final inlineMapCall = mapHasOwnPropertyCall(fn, args);
		if(inlineMapCall != null) {
			return inlineMapCall;
		}
		final rendered = argTexts(fn, args).join(", ");
		switch(fn.expr) {
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
				final module = cls.module != "" ? cls.module : (cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name);
				if(cls.pack.length == 0 && cls.name == "StringTools" && fName == "hex") {
					return stringToolsHex(args);
				}
				if(module == "std.UStringPlatform") {
					return ustringPlatformCall(fName, args, fn);
				}
				if(module == "std.TestPlatform") {
					return testPlatformCall(fName, args, fn);
				}
				if(module == "std.UStringRT") {
					return residentCall("UString", args, fn);
				}
				if(module == "std.Graphemes") {
					return residentCall("Graphemes", args, fn);
				}
				if(module == "Math") {
					// Members with no bare-function form lower onto the
					// stdlib method or property of the argument.
					switch(fName) {
						case "floor": return "(" + expr(args[0]) + ").rounded(.down)";
						case "ceil": return "(" + expr(args[0]) + ").rounded(.up)";
						case "sqrt": return "(" + expr(args[0]) + ").squareRoot()";
						case "isNaN": return "(" + expr(args[0]) + ").isNaN";
						case _:
					}
				}
				if(module == "String" && cls.pack.length == 0 && fName == "fromCharCode") {
					// The char domain of the subset stays inside valid
					// scalars; the force unwrap states that contract.
					return "String(UnicodeScalar(UInt32(bitPattern: " + expr(args[0]) + "))!)";
				}
				if(module == "Std") {
					if(fName == "int") {
						final arg = stripWrap(args[0]);
						switch(arg.expr) {
							case TBinop(OpDiv, l, r) if(isIntTyped(l) && isIntTyped(r)):
								// Truncating division of two Ints: the
								// operands are already integral.
								return expr(l) + " / " + expr(r);
							case _:
						}
						return "Int32(" + expr(args[0]) + ")";
					}
					if(fName == "string") {
						return stdString(args[0], false);
					}
				}
				if(module == "std.Test") {
					return testCall(fName, args, fn);
				}
				if((cls.name == "Functional" || cls.name == "__functional_shim" || module == "std.Functional") && fName == "sortedBy") {
					return sortedByCall(args, fn);
				}
				if(module == "std.SortedMap" && fName == "builder") {
					// Swift call sites never spell generic arguments; the
					// declaration annotation carries them instead.
					imports.runtime("SortedTable");
					return "SortedTable.mapBuilder(" + sortedComparator(kTypeOf(fn), fn.pos) + ")";
				}
				if(module == "std.SortedSet" && fName == "builder") {
					imports.runtime("SortedTable");
					return "SortedTable.setBuilder(" + sortedComparator(kTypeOf(fn), fn.pos) + ")";
				}
			case _:
		}
		switch(fn.expr) {
			case TCast(inner, _):
				return call(inner, args);
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return "Int32(" + expr(subj) + ".count)";
			case TField(subj, FInstance(_, _, cf)):
				final name = cf.get().name;
				if(isStringSubject(subj)) {
					if(name == "toLowerCase") return expr(subj) + ".lowercased()";
					if(name == "toUpperCase") return expr(subj) + ".uppercased()";
				}
				if(isMapType(subj.t)) {
					if(name == "exists" && args.length == 1) return expr(subj) + "[" + expr(args[0]) + "] != nil";
					if(name == "get" && args.length == 1) return expr(subj) + "[" + expr(args[0]) + "]";
					if(name == "set" && args.length == 2) return expr(subj) + "[" + expr(args[0]) + "] = " + expr(args[1]);
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
				}
				final folded = constantAsciiFold(subj, name, args);
				if(folded != null) {
					return folded;
				}
				// stdlib/01: Bytes.get(i) is a UInt8 index read widened
				// to Int32.
				if(name == "get" && isBytes(stripCast(subj))) {
					return "Int32(" + receiverText(subj) + "[Int(" + expr(args[0]) + ")])";
				}
				if(name == "push") {
					return receiverText(subj) + ".append(" + rendered + ")";
				}
				if(name == "join") {
					return receiverText(subj) + ".joined(separator: " + rendered + ")";
				}
				if(name == "slice") {
					return "Array(" + receiverText(subj) + "[Int(" + expr(args[0]) + ")..<Int(" + expr(args[1]) + ")])";
				}
				if(name == "substring" && isStringSubject(subj)) {
					// The haxe typer passes a synthesized null for an
					// omitted ?endIndex; the platform one-argument
					// overload carries the suffix call.
					final endOmitted = args.length < 2 || switch(stripWrap(args[1]).expr) {
						case TConst(TNull): true;
						case _: false;
					};
					final s = receiverText(subj);
					if(types.resident) {
						// The resident subject is already the unit array.
						return endOmitted
							? "Array(" + s + "[Int(" + expr(args[0]) + ")...])"
							: "Array(" + s + "[Int(" + expr(args[0]) + ")..<Int(" + expr(args[1]) + ")])";
					}
					if(endOmitted) {
						// dropFirst would count Characters, not UTF-16
						// units; the suffix cut walks the unit view.
						return "String(decoding: " + s + ".utf16.dropFirst(Int(" + expr(args[0]) + ")), as: UTF16.self)";
					}
					return "substringUnits(" + s + ", " + expr(args[0]) + ", " + expr(args[1]) + ")";
				}
				if(name == "charCodeAt" && isStringSubject(subj)) {
					return types.resident
						? "Int32(" + receiverText(subj) + "[Int(" + expr(args[0]) + ")])"
						: "unitAt(" + receiverText(subj) + ", " + expr(args[0]) + ")";
				}
				return receiverText(subj) + "." + name + "(" + rendered + ")";
			case TField(_, FEnum(en, ef)):
				return enumConstruct(en.get().name, ef, args);
			case TConst(TSuper):
				// The exception base initializes through its message.
				if(args.length == 0) {
					return "super.init(message: \"\")";
				}
				return "super.init(message: " + rendered + ")";
			case _:
				return expr(fn) + "(" + rendered + ")";
		}
	}

	/**
		std.UStringRT and std.Graphemes call sites: string arguments
		convert once into the resident unit array and string results
		decode back, the resident ABI of docs/specs/targets/swift.md.
	**/
	function residentCall(resident: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		imports.runtime(resident);
		final fName = switch(fn.expr) {
			case TField(_, FStatic(_, cf)): cf.get().name;
			case _: "";
		};
		final converted = [for(a in args) isStringSubject(a) && !types.resident ? unitArrayText(a) : expr(a)];
		final callText = resident + "." + fName + "(" + converted.join(", ") + ")";
		return switch(Context.follow(fn.t)) {
			case TFun(_, ret): wrapResidentStringResult(callText, ret);
			case _: callText;
		};
	}

	/**
		String results decode once at the boundary; optionals and string
		arrays decode element-wise through map. `Context.follow` is off
		here: it would unwrap Null<T> to T and lose the optionality.
	**/
	function wrapResidentStringResult(callText: String, ret: Type): String {
		return switch(ret) {
			case TAbstract(a, params) if(a.get().name == "Null" && !types.resident):
				switch(params[0]) {
					case TInst(c, _) if(c.get().name == "String"):
						callText + ".map { String(decoding: $0, as: UTF16.self) }";
					case _:
						callText;
				}
			case TInst(c, _) if(c.get().name == "String" && !types.resident):
				"String(decoding: " + callText + ", as: UTF16.self)";
			case TInst(c, params) if(c.get().name == "Array" && !types.resident):
				switch(params[0]) {
					case TInst(inner, _) if(inner.get().name == "String"):
						callText + ".map { String(decoding: $0, as: UTF16.self) }";
					case _:
						callText;
				}
			case TLazy(f):
				wrapResidentStringResult(callText, f());
			case _:
				callText;
		};
	}

	/**
		Cursor primitives of the resident UString walk, inlined per call
		against the unit array: end is the unit count, codeAt is an
		integer subscript, advance adds the surrogate-pair width, and
		fromCodePoint encodes the scalar (an out-of-domain argument
		yields the NUL replacement, matching the Rust lane). Business
		code never reaches these; it calls std.UString.
	**/
	function ustringPlatformCall(fName: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		if(!imports.selfResident) {
			Context.error("std.UStringPlatform is a resident runtime primitive; business code calls std.UString", fn.pos);
		}
		switch(fName) {
			case "end":
				return "Int32(" + expr(args[0]) + ".count)";
			case "codeAt":
				// The pair-combining read: a supplementary scalar returns
				// combined, not its high unit.
				return "unitCodePoint(" + expr(args[0]) + ", " + expr(args[1]) + ")";
			case "advance":
				final s = expr(args[0]);
				final i = expr(args[1]);
				// The width literal names Int32; a bare literal would
				// infer Int and mix with the Int32 cursor.
				return "(" + i + " + Int32(unitCodePoint(" + s + ", " + i + ") > 0xFFFF ? 2 : 1))";
			case "substringBetween":
				return "Array(" + expr(args[0]) + "[Int(" + expr(args[1]) + ")..<Int(" + expr(args[2]) + ")])";
			case "fromCodePoint":
				final cp = expr(args[0]);
				return "((" + cp + " >= 0 && " + cp + " <= 1114111 && !(" + cp + " >= 55296 && " + cp + " <= 57343)) ? ("
					+ cp + " > 65535 ? [UInt16(55296 + ((" + cp + " - 65536) >> 10)), UInt16(56320 + (" + cp + " & 1023))] : [UInt16(" + cp + ")])"
					+ " : [UInt16(0)])";
			case _:
				return fail(fn, "UStringPlatform." + fName + " has no Swift lowering");
		}
	}

	/**
		Host edges of the resident runtime.TestCore, inlined per call:
		raising is a throw of the host failure type, the running test id
		lives in the Test host of this same test entry, and plain numbers
		render through String. Business code never reaches these; it
		calls std.Test.
	**/
	function testPlatformCall(fName: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		if(!imports.selfResident) {
			Context.error("std.TestPlatform is a resident runtime primitive; business code calls std.Test", fn.pos);
		}
		switch(fName) {
			case "raise":
				imports.runtimeTest("TestFailure");
				return "throw TestFailure(message: " + expr(args[0]) + ")";
			case "currentTestId":
				imports.runtimeTest("Test");
				return "Test.currentTestIdState()";
			case "intToString":
				return "Array(String(" + expr(args[0]) + ").utf16)";
			case "floatToString":
				return "Array(String(" + expr(args[0]) + ").utf16)";
			case _:
				return fail(fn, "TestPlatform." + fName + " has no Swift lowering");
		}
	}

	/**
		std.Test assertions: scalars route to the TestCore checks with
		the message converted once; composite values route to the
		generated assertion of their tag (features/19).
	**/
	function testCall(fName: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		imports.runtimeTest("TestCore");
		switch(fName) {
			case "ok":
				return "TestCore.ok(" + expr(args[0]) + ", " + testMessageUnits(args, 1) + ")";
			case "fail":
				return "TestCore.fail(" + testMessageUnits(args, 0) + ")";
			case "equals":
				// The assertion type comes from the actual value: the
				// expected side may be the bare null literal, and
				// following it would unwrap the optionality the route
				// needs to see.
				final t = equalsAssertType(args);
				final message = testMessageUnits(args, 2);
				if(SwiftTestTypes.isScalarRoute(t)) {
					return switch(t) {
						case TAbstract(a, _) if(a.get().name == "Int"): "TestCore.equalsInt(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case TAbstract(a, _) if(a.get().name == "Float"): "TestCore.equalsFloat(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case TAbstract(a, _) if(a.get().name == "Bool"): "TestCore.equalsBool(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case TInst(c, _) if(c.get().name == "String"):
							"TestCore.equalsString(" + unitArrayText(args[0]) + ", " + unitArrayText(args[1]) + ", " + message + ")";
						case _: fail(fn, "test assertion type has no Swift lowering");
					};
				}
				final tag = SwiftTestTypes.register(t);
				return "assertEquals" + tag + "(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
			case _:
				return fail(fn, "std.Test." + fName + " has no Swift lowering");
		}
	}

	/**
		The type a Test.equals assertion compares: the actual value's own
		type, unfollowed so Null wrappers keep their optionality. The
		expected side is the fallback when the actual carries no type.
	**/
	function equalsAssertType(args: Array<TypedExpr>): Type {
		if(args.length > 1 && args[1].t != null) {
			return args[1].t;
		}
		return args[0].t;
	}

	/** The message argument as the resident unit array; null renders empty. */
	function testMessageUnits(args: Array<TypedExpr>, index: Int): String {
		if(args.length <= index) {
			return "[]";
		}
		final m = args[index];
		switch(stripWrap(m).expr) {
			case TConst(TNull): return "[]";
			case _:
		}
		return switch(Context.follow(m.t)) {
			case TAbstract(a, _) if(a.get().name == "Null"): "Array((" + expr(m) + " ?? \"\").utf16)";
			case _: unitArrayText(m);
		};
	}

	/**
		The unit-array conversion of one string expression: postfix
		subjects bind `.utf16` directly, infix forms (a concatenation, a
		ternary) take parentheses first or the view would attach to the
		last operand alone.
	**/
	function unitArrayText(a: TypedExpr): String {
		final text = expr(a);
		return switch(stripWrap(a).expr) {
			case TBinop(_, _, _) | TIf(_, _, _): "Array((" + text + ").utf16)";
			case _: "Array(" + text + ".utf16)";
		};
	}

	/**
		The one pipeline call the expander leaves in place: sorting by a
		key function. The comparator closure binds the key expressions
		under the expander's parameter names; string keys compare through
		the unit-order helper because the native operators order by
		canonical equivalence (stdlib/07).
	**/
	function sortedByCall(args: Array<TypedExpr>, fn: TypedExpr): String {
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
			final comparator = isStringLeafType(bodyExpr.t)
				? "compareUnitOrder(" + keyA + ", " + keyB + ") < 0"
				: keyA + " < " + keyB;
			return expr(receiver) + ".sorted { _a, _b in " + comparator + " }";
		}
		return fail(fn, "sortedBy requires a single-parameter key function");
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
		(stdlib/07): integers take the resident comparator, strings take
		the unit-order helper of the runtime prelude (business keys stay
		native String), structures take the per-type generated
		comparison.
	**/
	function sortedComparator(kType: Null<Type>, pos: haxe.macro.Expr.Position): String {
		if(kType == null) {
			Context.error("sorted builder requires an explicit key type", pos);
		}
		return switch(SwiftType.classifyKey(kType, pos)) {
			case SwiftIntKey:
				imports.runtime("SortedTable");
				"SortedTable.compareInts";
			case SwiftStringKey:
				imports.runtime("compareUnitOrder");
				"compareUnitOrder";
			case SwiftStructKey(def, _):
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

	/** A variant construct renders fully qualified; labels carry the payload names. */
	function enumConstruct(enumName: String, ef: EnumField, args: Array<TypedExpr>): String {
		final parts = [for(a in args) expr(a)];
		final names = payloadNames(ef);
		final labeled = [];
		for(i in 0...parts.length) {
			final pname = i < names.length ? names[i] : "v" + i;
			labeled.push(pname + ": " + parts[i]);
		}
		return labeled.length == 0
			? enumName + "." + SwiftDecl.lowerFirst(ef.name)
			: enumName + "." + SwiftDecl.lowerFirst(ef.name) + "(" + labeled.join(", ") + ")";
	}

	function newExpr(c: Ref<ClassType>, params: Array<Type>, args: Array<TypedExpr>): String {
		final cls = c.get();
		final rendered = [for(a in args) expr(a)].join(", ");
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return "[UInt16]()";
			case "haxe.ds._Map.Map_Impl_":
				return "[:]";
			case "haxe.io.BytesBuffer":
				imports.runtime("BytesBuffer");
				return "BytesBuffer()";
			case "Array":
				return "[" + types.of(params[0]) + "]()";
			case _:
				imports.value(cls.module, cls.name);
				return cls.name + "(" + rendered + ")";
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
				receiver == null ? null : expr(receiver) + "[" + expr(args[1]) + "] != nil";
			case _: null;
		};
	}

	function assignTarget(e: TypedExpr): String {
		switch(e.expr) {
			case TArray(arr, idx):
				return expr(arr) + "[Int(" + expr(idx) + ")]";
			case TField(_, FStatic(c, cf)):
				return staticRef(c.get(), cf.get().name);
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				return expr(subj) + "." + cf.get().name;
			case TLocal(v):
				return localName(v);
			case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
				return assignTarget(inner);
			case _:
				return fail(e, "assignment target has no Swift lowering");
		}
	}

	/**
		A record literal renders as the memberwise initializer of its
		named struct, with the parts reordered to the declaration order
		the initializer takes. The typer leaves the literal's own type
		anonymous even where unification matched the typedef, so the
		struct resolves through the shape registry when the expression
		type carries no name.
	**/
	function objectLiteral(e: TypedExpr, fields: Array<{name: String, expr: TypedExpr}>): String {
		final def = resolveRecordDef(e.t);
		if(def == null) {
			return fail(e, "object literal must be typed by a named record typedef");
		}
		final byName = new Map<String, TypedExpr>();
		for(f in fields) {
			byName.set(f.name, f.expr);
		}
		final parts = [];
		for(name in recordFieldNames(def)) {
			final value = byName.get(name);
			if(value == null) {
				return fail(e, "record literal misses field " + name);
			}
			parts.push(name + ": " + expr(value));
		}
		return def.name + "(" + parts.join(", ") + ")";
	}

	/** The named record behind a literal's type: direct when named, by shape when the typer kept it anonymous. */
	function resolveRecordDef(t: Null<Type>): Null<DefType> {
		if(t == null) {
			return null;
		}
		return switch(Context.follow(t)) {
			case TType(d, _): d.get();
			case TAnonymous(anon):
				final def = SwiftDecl.structTypedefs.get(SwiftDecl.structureSignature(anon));
				def == null ? null : def.get();
			case TLazy(f): resolveRecordDef(f());
			case _: null;
		};
	}

	/** The record's field names in declaration order, alias chains followed. */
	function recordFieldNames(def: DefType): Array<String> {
		return switch(def.type) {
			case TAnonymous(anon):
				final fields = anon.get().fields.copy();
				fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
				[for(f in fields) f.name];
			case TType(inner, _): recordFieldNames(inner.get());
			case _:
				Context.error("record typedef must be a structure", def.pos);
				[];
		}
	}

	// ------------------------------------------------------------------
	// Try regions (features/06)
	// ------------------------------------------------------------------

	/**
		Try regions lower as native do/catch with typed catch patterns.
		A typed pattern never makes the statement exhaustive, so every
		region closes with a bare rethrow arm; the enclosing function
		carries `throws` for exactly the domains no pattern names. The
		pattern binds the error only when the handler reads it.
	**/
	function isTryRegion(e: TypedExpr): Bool {
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

	/** The emitted class name behind the catch pattern, with its reference registered. */
	function exceptionClassOf(c: {v: TVar, expr: TypedExpr}): Null<String> {
		return switch(Context.follow(c.v.t)) {
			case TInst(cls, _):
				imports.value(cls.get().module, cls.get().name);
				cls.get().name;
			case _: null;
		};
	}

	/** Whether the handler reads the caught variable. */
	function handlerBindsError(c: {v: TVar, expr: TypedExpr}): Bool {
		return mentionsLocal(c.expr, c.v);
	}

	/**
		Splits a region body or handler into its leading statements and its
		trailing value expression; control-flow tails carry no value. A
		trailing checked toString carries its own check statements ahead of
		the decoded value it produces.
	**/
	/**
		Whether a statement-position expression is a call whose result the
		source discards: the callee returns a non-Void value Swift would
		flag. Array push is the exception: it returns the new length in
		Haxe but lowers to the Void-returning append.
	**/
	function isDiscardedCall(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TCall(fn, _):
				switch(stripWrap(fn).expr) {
					case TField(_, fa) if(fieldName(fa) == "push"): false;
					case _:
						switch(Context.follow(fn.t)) {
							case TFun(_, ret):
								switch(Context.follow(ret)) {
									case TAbstract(a, _): a.get().name != "Void";
									case _: true;
								}
							case _: false;
						}
				}
			case _: false;
		};
	}

	/**
		Whether a region arm's statement prefix throws before its value:
		everything after the throw is unreachable, so the trailing
		assignment or return never renders.
	**/
	function armPrefixThrows(e: TypedExpr): Bool {
		for(s in statementsOf(e)) {
			switch(s.expr) {
				case TThrow(_): return true;
				case _:
			}
		}
		return false;
	}

	function blockValueLines(e: TypedExpr, depth: Int): {lines: Array<String>, value: Null<String>} {
		final stmts = statementsOf(e);
		var value: Null<String> = null;
		var body = stmts;
		if(stmts.length > 0) {
			final last = stmts[stmts.length - 1];
			if(isStringBufToStringCall(last)) {
				final subj = stringBufToStringSubject(stripWrap(last));
				final lines = blockLines(stmts.slice(0, stmts.length - 1), depth);
				final checks = stringBufToStringCheckLines(subj, depth);
				return {lines: lines.concat(checks), value: "String(decoding: " + expr(subj) + ", as: UTF16.self)"};
			}
			switch(last.expr) {
				case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TBlock(_) | TBreak | TContinue | TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
				case _:
					value = expr(last);
					body = stmts.slice(0, stmts.length - 1);
			}
		}
		return {lines: blockLines(body, depth), value: value};
	}

	function catchHeaderLine(c: {v: TVar, expr: TypedExpr}, clsName: String, depth: Int): String {
		if(handlerBindsError(c)) {
			return indent(depth) + "} catch let " + localName(c.v) + " as " + clsName + " {";
		}
		return indent(depth) + "} catch is " + clsName + " {";
	}

	function catchFooterLines(depth: Int): Array<String> {
		return [
			indent(depth) + "} catch {",
			indent(depth + 1) + "throw error",
			indent(depth) + "}"
		];
	}

	/** Statement-position region: the handler runs as a block. */
	function tryStatementLines(body: TypedExpr, c: {v: TVar, expr: TypedExpr}, depth: Int): Array<String> {
		final clsName = exceptionClassOf(c);
		if(clsName == null) {
			return fail(c.expr, "try region catch type is not an exception class");
		}
		final out = [indent(depth) + "do {"];
		for(l in blockLines(statementsOf(body), depth + 1)) out.push(l);
		out.push(catchHeaderLine(c, clsName, depth));
		catchVars.set(c.v.id, true);
		final handler = blockLines(statementsOf(c.expr), depth + 1);
		catchVars.remove(c.v.id);
		for(l in handler) out.push(l);
		for(l in catchFooterLines(depth)) out.push(l);
		return out;
	}

	/**
		Initializer-position region: definite initialization lets the
		binding hoist to a let with both arms assigning it.
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
		final kw = mutated.exists(v.id) ? "var" : "let";
		final out = [
			indent(depth) + kw + " " + name + ": " + types.of(v.t),
			indent(depth) + "do {"
		];
		final body = blockValueLines(parts.body, depth + 1);
		if(body.value == null) {
			return fail(region, "try region body has no value");
		}
		for(l in body.lines) out.push(l);
		final bodyTry = containsThrowingCall(stripToValue(parts.body)) ? "try " : "";
		if(!armPrefixThrows(parts.body)) {
			out.push(indent(depth + 1) + name + " = " + bodyTry + body.value);
		}
		out.push(catchHeaderLine(parts.c, clsName, depth));
		catchVars.set(parts.c.v.id, true);
		final handler = blockValueLines(parts.c.expr, depth + 1);
		catchVars.remove(parts.c.v.id);
		if(handler.value == null) {
			return fail(parts.c.expr, "try region handler has no value");
		}
		for(l in handler.lines) out.push(l);
		final handlerTry = containsThrowingCall(stripToValue(parts.c.expr)) ? "try " : "";
		if(!armPrefixThrows(parts.c.expr)) {
			out.push(indent(depth + 1) + name + " = " + handlerTry + handler.value);
		}
		for(l in catchFooterLines(depth)) out.push(l);
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
		final out = [indent(depth) + "do {"];
		final body = blockValueLines(parts.body, depth + 1);
		if(body.value == null) {
			return fail(region, "try region body has no value");
		}
		for(l in body.lines) out.push(l);
		final bodyTry = containsThrowingCall(stripToValue(parts.body)) ? "try " : "";
		if(!armPrefixThrows(parts.body)) {
			out.push(indent(depth + 1) + "return " + bodyTry + body.value);
		}
		out.push(catchHeaderLine(parts.c, clsName, depth));
		catchVars.set(parts.c.v.id, true);
		final handler = blockValueLines(parts.c.expr, depth + 1);
		catchVars.remove(parts.c.v.id);
		if(handler.value == null) {
			return fail(parts.c.expr, "try region handler has no value");
		}
		for(l in handler.lines) out.push(l);
		final handlerTry = containsThrowingCall(stripToValue(parts.c.expr)) ? "try " : "";
		if(!armPrefixThrows(parts.c.expr)) {
			out.push(indent(depth + 1) + "return " + handlerTry + handler.value);
		}
		for(l in catchFooterLines(depth)) out.push(l);
		return out;
	}

	/**
		The trailing value expression of a region arm, wrapper-tolerant:
		the try marker resolution scans the value expression, not the
		statements around it.
	**/
	function stripToValue(e: TypedExpr): TypedExpr {
		final stmts = statementsOf(e);
		if(stmts.length == 0) {
			return e;
		}
		final last = stmts[stmts.length - 1];
		return switch(last.expr) {
			case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TBlock(_) | TBreak | TContinue | TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _): e;
			case _: last;
		}
	}

	// ------------------------------------------------------------------
	// String buffer checks (stdlib/08)
	// ------------------------------------------------------------------

	/**
		stdlib/08 string-buffer checks (Swift): every checked operation
		reads the trailing UTF-16 unit through the integer subscript, and
		the fault constructs the compiled std.UStringException with the
		UnpairedSurrogate variant. A throw is a statement here, so the
		checked operations lower at statement, binding, or return
		position only. An empty buffer holds no trailing unit; -1 fails
		every range check the way the NaN tail read of the TS lane does.
	**/
	function stringBufMutationParts(fn: TypedExpr): Null<{name: String, subj: TypedExpr}> {
		return switch(fn.expr) {
			case TField(subj, FInstance(_, _, cf)) if(isStringBuf(subj)):
				final n = cf.get().name;
				n == "add" || n == "addChar" ? {name: n, subj: subj} : null;
			case _: null;
		};
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
		}
	}

	function freshTailName(): String {
		stringBufTailCounter += 1;
		return stringBufTailCounter == 1 ? "tail" : "tail" + stringBufTailCounter;
	}

	/** The trailing-unit read every check opens with. */
	function stringBufTailLines(subj: TypedExpr, depth: Int): {name: String, lines: Array<String>} {
		imports.value("std.UStringException", "UStringException");
		final name = freshTailName();
		final buf = expr(subj);
		return {
			name: name,
			lines: [indent(depth) + "let " + name + " = " + buf + ".count > 0 ? Int32(" + buf + "[" + buf + ".count - 1]) : -1"]
		};
	}

	function stringBufFaultThrow(depth: Int, unit: String): String {
		// The generated exception class initializes positionally (the
		// memberwise labels of a struct do not exist for classes).
		return indent(depth) + "throw UStringException(UStringFault.unpairedSurrogate(unit: " + unit + "))";
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
			// The added string starts with a trail unit or the held lead
			// stays paired: only the unpaired case faults.
			lines.push(indent(depth) + "if " + tail + " >= 55296 && " + tail + " <= 56319 && !(Array(" + part + ".utf16).count > 0 && Array(" + part + ".utf16)[0] >= 56320 && Array(" + part + ".utf16)[0] <= 57343) {");
			lines.push(stringBufFaultThrow(depth + 1, tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + " += Array(" + part + ".utf16)");
		} else {
			final u = expr(args[0]);
			lines.push(indent(depth) + "if " + u + " >= 56320 && " + u + " <= 57343 {");
			lines.push(indent(depth + 1) + "if !(" + tail + " >= 55296 && " + tail + " <= 56319) {");
			lines.push(stringBufFaultThrow(depth + 2, u));
			lines.push(indent(depth + 1) + "}");
			lines.push(indent(depth) + "} else if " + tail + " >= 55296 && " + tail + " <= 56319 {");
			lines.push(stringBufFaultThrow(depth + 1, tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + ".append(UInt16(bitPattern: Int16(truncatingIfNeeded: " + u + ")))");
		}
		return lines;
	}

	function stringBufToStringCheckLines(subj: TypedExpr, depth: Int): Array<String> {
		final tailRead = stringBufTailLines(subj, depth);
		final lines = tailRead.lines;
		final tail = tailRead.name;
		lines.push(indent(depth) + "if " + tail + " >= 55296 && " + tail + " <= 56319 {");
		lines.push(stringBufFaultThrow(depth + 1, tail));
		lines.push(indent(depth) + "}");
		return lines;
	}

	function stringBufToStringBindingLines(v: TVar, call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		final kw = mutated.exists(v.id) ? "var" : "let";
		lines.push(indent(depth) + kw + " " + localName(v) + " = String(decoding: " + expr(subj) + ", as: UTF16.self)");
		return lines;
	}

	function stringBufToStringReturnLines(call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		lines.push(indent(depth) + "return String(decoding: " + expr(subj) + ", as: UTF16.self)");
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

	// ------------------------------------------------------------------
	// Variant switches (stdlib/03)
	// ------------------------------------------------------------------

	/**
		A variant switch lowers as a switch statement over the cases of
		its Equatable enum. The arms extract payloads through pattern
		bindings; exhaustive cases need no default arm.
	**/
	function switchReturn(sw: TypedExpr, depth: Int): Array<String> {
		final switchParts = switch(sw.expr) {
			case TSwitch(subj, cases, def): {subj: subj, cases: cases, def: def};
			case _: return fail(sw, "not a switch");
		}
		final subj = stripWrap(switchParts.subj);
		final se = switch(subj.expr) {
			case TEnumIndex(inner): inner;
			case _: subj;
		}
		final subjRendered = expr(se);
		final table = enumTable(se);
		final out = [indent(depth) + "switch " + subjRendered + " {"];
		for(c in switchParts.cases) {
			final index = switch(c.values[0].expr) {
				case TConst(TInt(v)): v;
				case _: return fail(sw, "variant switch case is not a constant index");
			}
			final info = table.get(index);
			if(info == null) {
				return fail(sw, "variant switch case index has no construct");
			}
			final names = payloadNames(info.field);
			final used = usedPayloadIndices(c.expr, info.field);
			final bindings = [for(i in 0...names.length) used.indexOf(i) >= 0 ? "let " + names[i] : "_"].join(", ");
			out.push(indent(depth + 1) + "case ." + SwiftDecl.lowerFirst(info.name) + (names.length > 0 ? "(" + bindings + ")" : "") + ":");
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
							Context.error("swift target: declaration without initializer has no lowering", s.pos);
						}
						switch(stripWrap(init).expr) {
							case TEnumParameter(se, ef, index):
								subst.set(v.id, payloadName(ef, index));
							case TLocal(source) if(subst.exists(source.id)):
								// The typer binds the switch subject to a hidden
								// local before extracting the payload; forward
								// the substitution through that chain.
								subst.set(v.id, subst.get(source.id));
							case _:
								out.push(indent(depth) + "let " + localName(v) + " = " + expr(init));
						}
					case TBlock(bs):
						walk(bs);
					case TMeta(_, inner):
						walk([inner]);
					case TReturn(r) if(r != null):
						value = expr(r);
					case _:
						value = expr(s);
				}
			}
		}
		walk(statementsOf(e));
		if(value == null) {
			return fail(e, "variant switch arm has no value");
		}
		out.push(indent(depth) + "return " + value);
		return out;
	}

	function enumTable(se: TypedExpr): Map<Int, {name: String, field: EnumField}> {
		final table = new Map<Int, {name: String, field: EnumField}>();
		switch(se.t) {
			case TEnum(e, _):
				final en = e.get();
				for(name => ef in en.constructs) {
					table.set(ef.index, {name: name, field: ef});
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
		};
	}

	/**
		The payload positions one arm reads. The typer binds every pattern
		variable through a hidden extraction local and, when the pattern
		names it, a forwarding declaration whose initializer is that local
		alone; a bare chain reference is the binding, not a use. A position
		counts as read only when the arm references the name it binds.
		Unread positions bind `_`; Swift warns on an unused `let` binding.
	**/
	function usedPayloadIndices(e: TypedExpr, ef: EnumField): Array<Int> {
		final live = new Map<Int, Bool>();
		final forwards = new Map<Int, Int>();
		final extraction = new Map<Int, Int>();
		function walk(x: TypedExpr) {
			switch(x.expr) {
				case TVar(v, init) if(init != null):
					switch(stripWrap(init).expr) {
						case TLocal(w):
							forwards.set(v.id, w.id);
						case TEnumParameter(_, ef2, index) if(ef2.index == ef.index):
							extraction.set(v.id, index);
							TypedExprTools.iter(init, walk);
						case _:
							TypedExprTools.iter(init, walk);
					}
				case TLocal(v):
					live.set(v.id, true);
				case _:
					TypedExprTools.iter(x, walk);
			}
		}
		walk(e);
		var changed = true;
		while(changed) {
			changed = false;
			for(vId => wId in forwards) {
				if(live.exists(vId) && !live.exists(wId)) {
					live.set(wId, true);
					changed = true;
				}
			}
		}
		final used: Array<Int> = [];
		for(vId => index in extraction) {
			if(live.exists(vId) && used.indexOf(index) < 0) {
				used.push(index);
			}
		}
		return used;
	}

	function payloadName(ef: EnumField, index: Int): String {
		final names = payloadNames(ef);
		return index < names.length ? names[index] : "v" + index;
	}

	// ------------------------------------------------------------------
	// String interpolation
	// ------------------------------------------------------------------

	/**
		Whether a `+` expression produces a string: Swift has no string
		concatenation with numbers, so a non-string leaf renders through
		interpolation instead (the TS lane relies on implicit coercion
		here).
	**/
	function isStringTyped(e: TypedExpr): Bool {
		return isStringLeafType(e.t);
	}

	function isStringLeafType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TInst(c, _): c.get().name == "String";
			case TLazy(f): isStringLeafType(f());
			case _: false;
		}
	}

	/**
		A string concatenation with any non-string leaf renders as a
		literal with interpolations; an all-string chain keeps the `+`
		operator. A leaf that is itself a weaker binary operator
		parenthesizes, because the flattened join no longer carries the
		nesting the operand rules would have restored.
	**/
	function templateLiteral(l: TypedExpr, r: TypedExpr): String {
		final leaves: Array<TypedExpr> = [];
		flattenAdd(l, leaves);
		leaves.push(r);
		var allStrings = true;
		for(leaf in leaves) {
			switch(leaf.expr) {
				case TConst(TString(_)):
				case _:
					final stdArg = stdStringArg(leaf);
					if(stdArg != null ? !isStringLeafType(stdArg.t) : !isStringLeafType(leaf.t)) {
						allStrings = false;
					}
			}
		}
		if(allStrings) {
			var out = "";
			for(i in 0...leaves.length) {
				out += (i > 0 ? " + " : "") + templateLeaf(leaves[i]);
			}
			return out;
		}
		final b = new StringBuf();
		b.addChar('"'.code);
		for(leaf in leaves) {
			switch(leaf.expr) {
				case TConst(TString(s)): b.add(escapeInterpolation(s));
				case _:
					final stdArg = stdStringArg(leaf);
					b.add("\\(" + (stdArg == null ? expr(leaf) : stdString(stdArg, true)) + ")");
			}
		}
		b.addChar('"'.code);
		return b.toString();
	}

	/**
		A flattened leaf: right-nested additions keep no parentheses;
		weaker operators take them. An optional String leaf unwraps: the
		source guards it null before the concatenation (the Haxe typer
		flows the checked value through), and Swift needs the unwrap a
		guarded local does not get implicitly.
	**/
	function templateLeaf(leaf: TypedExpr): String {
		return switch(stripWrap(leaf).expr) {
			case TBinop(OpAdd, _, _): expr(leaf);
			case TBinop(_, _, _): "(" + expr(leaf) + ")";
			case _: optionalStringLeaf(leaf) ? expr(leaf) + "!" : expr(leaf);
		};
	}

	/** Whether a concat leaf is an optional string a guard has cleared. */
	function optionalStringLeaf(leaf: TypedExpr): Bool {
		if(!optionalValued(leaf)) {
			return false;
		}
		return switch(Context.follow(leaf.t)) {
			case TInst(c, _): c.get().name == "String";
			case _: false;
		};
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
	// Throw marking (features/06)
	// ------------------------------------------------------------------

	/**
		Whether a statement's expression calls anything that can throw
		outside a nested try region: Swift marks every throwing call site
		with `try`. Regions and closures lower their own bodies, so their
		subtrees never mark the enclosing statement.
	**/
	function containsThrowingCall(e: TypedExpr): Bool {
		var found = false;
		function walk(x: TypedExpr) {
			if(found) {
				return;
			}
			switch(x.expr) {
				case TTry(_, _):
					return;
				case TFunction(_):
					return;
				case TCall(fn, _):
					if(callTargetThrows(fn)) {
						found = true;
						return;
					}
					TypedExprTools.iter(x, walk);
				case TNew(c, _, _):
					// A construction of a throwing constructor needs the try
					// marker at its statement (feature spec 27).
					if(SwiftFallibility.isThrowing(c.get().module, "new", false)) {
						found = true;
						return;
					}
					TypedExprTools.iter(x, walk);
				case _:
					TypedExprTools.iter(x, walk);
			}
		}
		walk(e);
		return found;
	}

	function callTargetThrows(fn: TypedExpr): Bool {
		switch(fn.expr) {
			case TField(subj, FStatic(c, cf)):
				return SwiftFallibility.staticCallThrows(c.get(), cf.get().name);
			case TField(subj, FInstance(c, _, cf)):
				final name = cf.get().name;
				// The buffer checks lower with their own throw
				// statements; no try marker covers them.
				if(SwiftFallibility.isStringBufMethodCall(subj, name)) {
					return false;
				}
				return SwiftFallibility.isThrowing(c.get().module, name, false);
			case _:
				return false;
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
				if(init != null && isNullLeafType(init.t)) {
					optionalInferred.set(v.id, true);
				}
				case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
					switch(t.expr) {
						case TLocal(v):
							markMutated(v);
						case TArray(arr, _):
							// Storing through a subscript mutates the array
							// value itself.
							final receiver = mapBackingReceiver(arr);
							switch(stripWrap(receiver == null ? arr : receiver).expr) {
								case TLocal(v): markMutated(v);
								case _:
						}
					case _:
				}
			case TCall(fn, _):
				switch(fn.expr) {
					case TField(subj, FInstance(_, _, cf)):
						final n = cf.get().name;
							final mutates = (isStringBuf(subj) && (n == "add" || n == "addChar")) || n == "push" || n == "set";
						if(mutates) {
							switch(stripWrap(subj).expr) {
								case TLocal(v): markMutated(v);
								case _:
							}
						}
					case _:
				}
			case _:
		}
		TypedExprTools.iter(e, scanLocals);
	}

	function markMutated(v: TVar): Void {
		mutated.set(v.id, true);
		// Parameter writes surface by name only: the declaration site
		// holds the argument list, not the body's TVar objects.
		if(v.name != "`") {
			mutatedNames.set(v.name, true);
		}
	}

	/**
		Swift parameters are immutable; a body that writes one (directly,
		through a subscript, or through a mutating method) shadows it
		with a local of the same name at the top of the function. The
		parameter's own TVar decides: a same-named local elsewhere in
		the module must not shadow this one.
	**/
	public function shadowMutatedParams(args: Array<{name: String, ?tvar: Null<TVar>}>): Array<String> {
		final out: Array<String> = [];
		for(a in args) {
			if(a.name == null || a.name.length == 0) {
				continue;
			}
			final written = a.tvar != null && a.tvar.id != null
				? mutated.exists(a.tvar.id)
				: mutatedNames.exists(a.name);
			if(written) {
				out.push(indent(2) + "var " + a.name + " = " + a.name);
			}
		}
		return out;
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
			case OpEq: "==";
			case OpNotEq: "!=";
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
			case _: return fail(null, "operator has no Swift lowering");
		}
	}

	/**
		Swift's binary precedence table: shifts bind tightest, then
		multiplication with `&`, then addition with `|` and `^`, then
		comparisons, then the logical pair.
	**/
	function precedenceOf(op: Binop): Int {
		return switch(op) {
			case OpBoolOr: 1;
			case OpBoolAnd: 2;
			case OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte: 3;
			case OpAdd | OpSub | OpOr | OpXor: 7;
			case OpMult | OpDiv | OpMod | OpAnd: 8;
			case OpShl | OpShr | OpUShr: 9;
			case _: 0;
		}
	}

	function associative(op: Binop): Bool {
		return switch(op) {
			case OpOr | OpXor | OpAnd | OpBoolAnd | OpBoolOr | OpAdd | OpMult: true;
			case _: false;
		}
	}

	function isIntTyped(e: TypedExpr): Bool {
		return switch(Context.follow(e.t)) {
			case TAbstract(a, _): a.get().name == "Int";
			case TLazy(f): isIntLeafType(f());
			case _: false;
		}
	}

	function isIntLeafType(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Int";
			case _: false;
		}
	}

	function isFloatLeafType(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Float";
			case _: false;
		}
	}

	function isBytesType(e: TypedExpr): Bool {
		return isBytesLeafType(e.t);
	}

	function isBytesLeafType(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
			case TType(d, _):
				final def = d.get();
				def.pack.join(".") == "haxe.io" && def.name == "Bytes";
			case TLazy(f): isBytesLeafType(f());
			case _: false;
		}
	}

	/** Whether the initializer is an array literal with no elements. */
	function isEmptyArrayDecl(init: TypedExpr): Bool {
		return switch(stripWrap(init).expr) {
			case TArrayDecl(elems): elems.length == 0;
			case _: false;
		};
	}

	/**
		Whether the initializer is an array literal whose elements are
		integer literals (an integer literal, or a nested array of them).
		Swift infers such a literal as the 64-bit Int element type; the
		declaration annotation pins Int32 instead.
	**/
	function isIntLiteralArrayDecl(init: TypedExpr): Bool {
		return switch(stripWrap(init).expr) {
			case TArrayDecl(elems):
				for(el in elems) {
					if(!isIntLiteralElement(el)) {
						return false;
					}
				}
				true;
			case _: false;
		};
	}

	function isIntLiteralElement(e: TypedExpr): Bool {
		return switch(stripWrap(e).expr) {
			case TConst(c):
				switch(c) {
					case TInt(_): true;
					case _: false;
				}
			case TArrayDecl(_): isIntLiteralArrayDecl(e);
			case _: false;
		};
	}

	/**
		Whether a type is the Null wrapper, without `Context.follow`:
		follow unwraps Null<T> to T and would lose the optionality the
		rendering needs to see.
	**/
	function isNullLeafType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(t) {
			case TAbstract(a, _): a.get().name == "Null";
			case TLazy(f): isNullLeafType(f());
			case _: false;
		};
	}

	/** Whether the initializer is a sorted-table builder factory call. */
	function isBuilderCall(init: TypedExpr): Bool {
		return switch(stripWrap(init).expr) {
			case TCall({expr: TField(_, FStatic(c, cf))}, _):
				final cls = c.get();
				(cls.module == "std.SortedMap" || cls.module == "std.SortedSet") && cf.get().name == "builder";
			case _: false;
		};
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
		return isBytesType(e);
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
		}
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

	function escapeInterpolation(s: String): String {
		final b = new StringBuf();
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
		return b.toString();
	}

	function indent(depth: Int): String {
		final b = new StringBuf();
		for(i in 0...depth) {
			b.add("    ");
		}
		return b.toString();
	}

	function fail(e: Null<TypedExpr>, message: String): Dynamic {
		final pos = e != null ? e.pos : Context.currentPos();
		Context.error("swift target: " + message, pos);
		return null;
	}
}
#end
