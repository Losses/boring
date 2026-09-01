package dartcompiler;

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
	Statement and expression lowering from the Haxe typed AST to Dart.
	Every lowering is named after the ruling that requires it and derives
	from the shapes the typer and the pipeline expander produce (counted
	loops arrive as two hidden TVar statements plus a TWhile; the loop
	variable is captured through a post-increment of the hidden counter).

	- features/09 IntervalLoopRecognition: the counted loop re-emits as
	  `for (var i = a; i < b; i++)`. The bound is the hoisted hidden
	  local, so the condition reads one TLocal per iteration.
	- features/09 CountedFillLowering: a fresh `<T>[]` filled by a
	  counted loop whose body only stores elements (indexed store or one
	  append) appends per iteration. Dart lists grow amortized, so the
	  capacity reservation of the Swift lane has no Dart counterpart.
	- stdlib/03 enum lowering: variants become subclasses of a sealed
	  class; construct comparisons read as `==` through the generated
	  equality; variant switches lower as exhaustive switch statements
	  over object patterns.
	- stdlib/04 ConstantAsciiFold: writeAscii of an all-ASCII constant
	  of width 4 or 2 folds to writeU32/writeU16 of the packed
	  big-endian word.
	- stdlib/01: haxe.io.Bytes.get(i) lowers to a plain list index read;
	  haxe.io.FPHelper bit conversions lower to the runtime helpers
	  (stdlib/05).
	- numbers ruling: Int is the 64-bit `int` of the VM exactly as
	  `number` carries the domain on the TypeScript lane; `/` on two
	  Int operands yields `double` natively (the Haxe semantics), and
	  Std.int of that division folds to `~/`.
**/
class DartExpr {
	final imports: DartImports;
	final types: DartType;

	/** Enum-capture locals mapped to the payload expression they stand for. */
	final subst: Map<Int, String> = [];

	/** Locals reassigned after their declaration; emitted with var. */
	final mutated: Map<Int, Bool> = [];

	/** Names written in the scanned body; parameters surface by name only. */
	final mutatedNames: Map<String, Bool> = [];

	/**
		Locals whose initializer is optional while the declared type is
		plain: the pipeline expander types a get()-initialized bucket as
		the plain value, and Dart infers the optional from the
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

	public function new(imports: DartImports, types: DartType) {
		this.imports = imports;
		this.types = types;
	}

	public function reserveName(name: String): Void {
		usedNames.set(name, true);
	}

	/** Binds a declaration parameter to its native extension receiver name. */
	public function bindLocalName(v: TVar, name: String): Void {
		subst.set(v.id, name);
	}

	/** Statements at library top level (the framework's expression entry). */
	public function topLevelStatements(e: TypedExpr): String {
		scanLocals(e);
		return blockLines(statementsOf(e), 0).join("\n");
	}

	/** One expression at current-statement position (the framework's expression entry). */
	public function rawExpression(e: TypedExpr): String {
		scanLocals(e);
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

	/** Renders the sanctioned expression in Dart expression position. */
	function coalescingDefaultText(value: DefaultArgExpander.CoalescingDefaultValue, targetType: Type): String {
		return switch(value) {
			case CInt(v): Std.string(v);
			case CFloat(s): s;
			case CString(s): quoteString(s);
			case CBool(b): b ? "true" : "false";
			case CNull: "null";
			case CEmptyArray:
				final element = switch(DefaultArgExpander.withoutNull(targetType)) {
					case TInst(c, params) if(c.get().name == "Array" && params.length > 0): types.of(params[0]);
					case TAbstract(a, params) if(a.get().name == "ReadOnlyArray" && params.length > 0): types.of(params[0]);
					case TType(_, params) if(params.length > 0): types.of(params[0]);
					case _: "dynamic";
				};
				"<" + element + ">[]";
			case CEmptyMap:
				final mapParams = switch(DefaultArgExpander.withoutNull(targetType)) {
					case TType(def, params) if(def.get().name == "Map" && params.length == 2): params;
					case TAbstract(def, params) if(def.get().pack.join(".") == "haxe.ds" && def.get().name == "Map" && params.length == 2): params;
					case _: [];
				};
				mapParams.length == 2
					? "<" + types.of(mapParams[0]) + ", " + types.of(mapParams[1]) + ">{}"
					: "<dynamic, dynamic>{}";
			case CPositiveInfinity: "double.infinity";
			case CNegativeInfinity: "-double.infinity";
			case CEnum(enumRef, enumField):
				final en = enumRef.get();
				isValueEnum(en) ? en.name + "." + DartDecl.lowerFirst(enumField.name) : en.name + enumField.name + "()";
			case CParameterRead(name):
				// Spec 22, Evaluation ordering: a read of an earlier coalescing
				// parameter resolves through that parameter's own default, so
				// the raw nullable binding wraps in its default here.
				final earlier = currentClass != null && currentField != null
					? (currentLocalName != null
						? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, name)
						: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, name))
					: null;
				earlier != null ? "(" + name + " ?? " + coalescingDefaultText(earlier, targetType) + ")" : name;
			case CFieldAccess(CParameterRead(staticPath), ""): coalescingStaticFieldText(staticPath);
			case CFieldAccess(receiver, fieldName): coalescingDefaultText(receiver, targetType) + "." + fieldName;
			case CMethodCall(receiver, methodName, args):
				coalescingDefaultText(receiver, targetType) + "." + methodName + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CStaticCall(fullPath, args):
				fullPath + "(" + [for(a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
			case CConditional(c, t, f):
				"(" + coalescingDefaultText(c, targetType) + " ? " + coalescingDefaultText(t, targetType) + " : " + coalescingDefaultText(f, targetType) + ")";
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
			case _: "?";
		};
	}

	function coalescingDefaultTextFor(site: {parameter: String, defaultExpr: TypedExpr, valueExpr: TypedExpr}): String {
		if(currentClass != null && currentField != null) {
			final value = currentLocalName != null
				? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, site.parameter)
				: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, site.parameter);
			if(value != null) {
				return coalescingDefaultText(value, DefaultArgExpander.withoutNull(site.valueExpr.t));
			}
		}
		return expr(site.defaultExpr);
	}

	// ------------------------------------------------------------------
	// Function bodies
	// ------------------------------------------------------------------

	public function functionBody(cls: ClassType, f: ClassFuncData, depth: Int = 2): Array<String> {
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
		return blockLines(statementsOf(f.expr), depth);
	}

	/** Body lowering for a member declared on a value wrapper. */
	public function valueTypeFunctionBody(cls: ClassType, f: ClassFuncData, fieldName: String): Array<String> {
		final abs = ValueTypeSupport.markedAbstractOfClass(cls);
		final op = abs == null ? null : ValueTypeSupport.operatorOf(abs, f.field);
		if(op != null) {
			if(f.args.length > 0) bindLocalName(f.args[0].tvar, fieldName);
			if(f.args.length > 1) bindLocalName(f.args[1].tvar, "other");
		} else if(ValueTypeSupport.hasReceiver(f.field) && f.args.length > 0) {
			bindLocalName(f.args[0].tvar, fieldName);
		}
		return functionBody(cls, f, 2);
	}

	/** Drops Haxe's synthetic representation assignment from a validating factory. */
	public function valueTypeConstructorBody(cls: ClassType, f: ClassFuncData): Array<String> {
		if(f.expr == null) Context.error("value type constructor has no body to lower", f.field.pos);
		DefaultArgExpander.completeRootExpr(cls, f.field.name, f.expr);
		PipelineExpander.expandRootExpr(f.expr);
		EnumQueryExpander.expandRootExpr(f.expr);
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
		scanLocals(f.expr);
		final out:Array<String> = [];
		for(stmt in statementsOf(f.expr)) {
			if(ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt)) continue;
			for(line in stmtLines(stmt, 1)) out.push(line);
		}
		return out;
	}

	/**
		Constructor emission pieces: assignments of `this.field` to their
		own parameter become initializing formals (keyed by parameter
		name), the remaining field assignments become the initializer
		list, the super call is kept apart so it renders last (Dart only
		allows the superinitializer at the end of the list), and the rest
		keeps statement form (Dart forbids assigning a final field in the
		constructor body).
	**/
	public function constructorParts(cls: ClassType, f: ClassFuncData): {formalFields: Map<String, String>, fieldInits: Array<String>, superCall: Null<String>, body: Array<String>} {
		if(f.expr == null) {
			Context.error("constructor has no body to lower", f.field.pos);
		}
		currentClass = cls;
		currentField = f.field.name;
		currentLocalName = null;
		scanLocals(f.expr);
		final formalFields = new Map<String, String>();
		final fieldInits: Array<String> = [];
		var superCall: Null<String> = null;
		final body: Array<String> = [];
		for(stmt in statementsOf(f.expr)) {
			switch(stmt.expr) {
				case TBinop(OpAssign, target, value):
					switch(stripWrap(target).expr) {
						case TField({expr: TConst(TThis)}, FInstance(owner, _, cf)):
							final coalescing = coalescingSiteFor(value);
							if(coalescing != null) {
								for(l in stmtLines(stmt, 2)) body.push(l);
								continue;
							}
							// A private field initializes under its
							// `_`-prefixed Dart name (feature spec 27).
							final field = memberName(owner.get().module, cf, stmt.pos);
							final param = paramLocalOf(value, f);
							if(param != null) {
								formalFields.set(param, field);
							} else {
								fieldInits.push(field + " = " + expr(value));
							}
						case _:
							for(l in stmtLines(stmt, 2)) body.push(l);
					}
				case TCall({expr: TConst(TSuper)}, args):
					superCall = "super(" + [for(a in args) expr(a)].join(", ") + ")";
				case _:
					for(l in stmtLines(stmt, 2)) body.push(l);
			}
		}
		return {formalFields: formalFields, fieldInits: fieldInits, superCall: superCall, body: body};
	}

	/**
		Instance fields a constructor initializes through a coalescing
		site in the body. Dart's definite-assignment analysis credits
		field formals and initializer-list entries only, so those
		fields declare `late` (feature spec 22).
	**/
	public function coalescedBodyFields(cls: ClassType, funcFields: Array<ClassFuncData>): Map<String, Bool> {
		final out = new Map<String, Bool>();
		final savedClass = currentClass;
		final savedField = currentField;
		final savedLocal = currentLocalName;
		currentClass = cls;
		currentField = "new";
		currentLocalName = null;
		for(f in funcFields) {
			if(f.field.name != "new" || f.expr == null) {
				continue;
			}
			for(stmt in statementsOf(f.expr)) {
				switch(stmt.expr) {
					case TBinop(OpAssign, target, value):
						switch(stripWrap(target).expr) {
							case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
								if(coalescingSiteFor(value) != null) {
									out.set(cf.get().name, true);
								}
							case _:
						}
					case _:
				}
			}
		}
		currentClass = savedClass;
		currentField = savedField;
		currentLocalName = savedLocal;
		return out;
	}

	/** The constructor parameter a bare local reads, or null when the value is not one. */
	function paramLocalOf(e: TypedExpr, f: ClassFuncData): Null<String> {
		return switch(stripWrap(e).expr) {
			case TLocal(v):
				for(a in f.args) {
					if(a.name == v.name) {
						return v.name;
					}
				}
				null;
			case _: null;
		};
	}

	// ------------------------------------------------------------------
	// Statements
	// ------------------------------------------------------------------

	function statementsOf(e: TypedExpr): Array<TypedExpr> {
		return switch(e.expr) {
			case TBlock(stmts): stmts;
			case _: [e];
		};
	}

	function stmtLines(e: TypedExpr, depth: Int): Array<String> {
		return terminated(stmtLinesRaw(e, depth));
	}

	/**
		Statement termination: every line of a lowered statement ends on
		its own terminator. Openers, closers, case labels, and
		continuation commas already end on one; everything else takes a
		semicolon.
	**/
	function terminated(lines: Array<String>): Array<String> {
		for(i in 0...lines.length) {
			final t = StringTools.rtrim(lines[i]);
			if(t.length == 0) {
				continue;
			}
			final c = t.charAt(t.length - 1);
			if(c == "{" || StringTools.ltrim(t) == "}" || c == ";" || c == ":" || c == ",") {
				continue;
			}
			lines[i] = t + ";";
		}
		return lines;
	}

	function stmtLinesRaw(e: TypedExpr, depth: Int): Array<String> {
		switch(e.expr) {
			case TVar(v, init) if(init != null && isTryRegion(init)):
				return tryBindingLines(v, init, depth);
			case TVar(v, init) if(init != null && isStringBufToStringCall(init)):
				return stringBufToStringBindingLines(v, stripWrap(init), depth);
			case TVar(v, init) if(init != null):
				final kw = mutated.exists(v.id) ? "var" : "final";
				final coalescing = coalescingSiteFor(init);
				// One initializer cannot carry its type to Dart's
				// inference: a bare null infers Null and rejects the
				// later value assignment. The declaration names the
				// nullable type instead; a named type carries no
				// keyword when the binding reassigns.
				if(coalescing != null || isNullLeafType(v.t)) {
					final head = kw == "final" ? "final " : "";
					final coalescingValue = coalescing == null ? null : (currentLocalName != null
						? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, coalescing.parameter)
						: DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, coalescing.parameter));
					final localType = coalescingValue != null ? DefaultArgExpander.coalescingLocalType(coalescingValue, v.t) : v.t;
					final initText = switch(init.expr) {
						case TFunction(fn): functionLiteralNamed(v.name, fn);
						default: expr(init);
					};
					return [indent(depth) + head + types.of(localType) + " " + localName(v) + " = " + initText];
				}
				final initText = switch(init.expr) {
					case TFunction(fn): functionLiteralNamed(v.name, fn);
					default: expr(init);
				};
				return [indent(depth) + kw + " " + localName(v) + " = " + initText];
			case TVar(v, _):
				// A declaration without initializer: definite
				// initialization assigns it on every path before use.
				return [indent(depth) + types.of(v.t) + " " + localName(v)];
			case TBlock(stmts):
				return blockLines(stmts, depth);
			case TIf(c, t, f):
				return ifLines(c, t, f, depth);
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
				return [indent(depth) + "return"];
			case TReturn(ret):
				final inner = stripWrap(ret);
				switch(inner.expr) {
					case TSwitch(_, _, _):
						return switchReturn(inner, depth);
					case _:
						return [indent(depth) + "return " + expr(ret)];
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
				final map = mapAssignment(l);
				final target = map == null ? assignTarget(l) + " = " : expr(map.receiver) + "[" + expr(map.key) + "] = ";
				return [indent(depth) + target + expr(r)];
			case TBinop(OpAssignOp(inner), l, r):
				return [indent(depth) + assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r)];
			case _:
				return [indent(depth) + expr(e)];
		}
	}

	function ifLines(c: TypedExpr, t: TypedExpr, f: Null<TypedExpr>, depth: Int): Array<String> {
		final out = [indent(depth) + "if (" + expr(c) + ") {"];
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
						switch(stripWrap(stmts[j]).expr) {
							case TBinop(OpAssign, lhs, rhs):
								switch(stripWrap(lhs).expr) {
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
				for(l in terminated(fused)) out.push(l);
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
						};
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
		// An unread counter renders as `_i`: Dart does not bind a bare
		// underscore as a name.
		final name = readsIndex ? localName(loop.index) : "_i";
		final out = [
			indent(depth) + "for (var " + name + " = " + expr(loop.start) + "; " + name + " < " + expr(loop.bound) + "; " + name + "++) {"
		];
		for(l in blockLines(loop.body, depth + 1)) out.push(l);
		out.push(indent(depth) + "}");
		return out;
	}

	// ------------------------------------------------------------------
	// Counted fill (features/09)
	// ------------------------------------------------------------------

	/**
		CountedFillLowering: `TVar arr = new Array<T>()` immediately
		followed by a counted loop whose only use of arr is storing one
		element per iteration (an indexed store at the loop index, or a
		single push) appends per iteration. Dart lists are reference
		values and grow amortized, so no capacity reservation and no
		freeze discipline apply.
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
		};
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
		out.push(indent(depth) + "final " + arrName + " = <" + types.of(alloc.elem) + ">[]");
		out.push(indent(depth) + "for (var " + (readsIndex ? localName(loop.index) : "_i") + " = " + expr(loop.start) + "; " + (readsIndex ? localName(loop.index) : "_i") + " < " + expr(loop.bound) + "; " + (readsIndex ? localName(loop.index) : "_i") + "++) {");
		final nonStores: Array<TypedExpr> = [];
		for(s in loop.body) {
			final store = indexedStoreOf(s);
			if(store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + ".add(" + expr(store.value) + ")");
				continue;
			}
			final push = pushOf(s);
			if(push != null && push.arr.id == alloc.arr.id) {
				if(nonStores.length > 0) {
					for(l in blockLines(nonStores, depth + 1)) out.push(l);
					nonStores.resize(0);
				}
				out.push(indent(depth + 1) + arrName + ".add(" + expr(push.arg) + ")");
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
					case _: return fail(e, "constant has no Dart lowering");
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
				return expr(inner);
			case TObjectDecl(fields):
				return objectLiteral(e, fields);
			case TArrayDecl(elems):
				return arrayLiteral(e, elems);
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
				if(coalescing != null) return expr(coalescing.valueExpr) + " ?? " + coalescingDefaultTextFor(coalescing);
				return "(" + expr(c) + " ? " + expr(t) + " : " + expr(f) + ")";
			case _:
				return fail(e, "expression has no Dart lowering in the subset");
		}
	}

	/** Lowers an abstract implementation block to a Dart extension value. */
	function valueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr):String {
		final abs = ValueTypeSupport.markedAbstractOfType(wrapper.t);
		if(abs == null) return expr(value);
		final wrapperName = qualifiedRef(abs.module, abs.name);
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
					nativeOperator && field.name == currentField ? wrapperName + "(" + rendered + ")" : rendered;
				}
			case TUnop(op, _, subject):
				final field = ValueTypeSupport.unaryOperatorField(abs, op);
				if(field == null) expr(value) else {
					final asRepresentation = nativeOperator && field.name == currentField;
					final rendered = "-" + valueTypeOperand(subject, locals, abs, asRepresentation);
					nativeOperator && field.name == currentField ? wrapperName + "(" + rendered + ")" : rendered;
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
		final fieldName = abs == null ? "" : ValueTypeSupport.representationFieldName(abs);
		final alreadyRepresentation = switch(stripWrap(value).expr) {
			case TLocal(v) if(subst.exists(v.id) && subst.get(v.id) == fieldName): true;
			case _: false;
		};
		return asRepresentation && wrapperOperand && !alreadyRepresentation ? rendered + "." + fieldName : rendered;
	}

	function enumQuery(e:TypedExpr):Null<String> {
		switch(e.expr) {
			case TField(subj, fa): final name = switch(fa) { case FInstance(_, _, cf) | FAnon(cf): cf.get().name; case FDynamic(n): n; case _: ""; }; final en = EnumQueryExpander.collectionEnum(subj); if(name == "length" && en != null) return Std.string(EnumQueryExpander.constructorCount(en));
			case TArray(subj, index): final en = EnumQueryExpander.collectionEnum(subj); if(en != null) return (EnumQueryExpander.aliasEnum(subj) != null ? expr(subj) : qualifiedRef(en.module, en.name) + ".values") + "[" + expr(index) + "]";
			case _:
		}
		final kind = EnumQueryExpander.markerKind(e); if(kind == null) return null; final en = EnumQueryExpander.enumOf(e); final args = EnumQueryExpander.callArgs(e);
		return switch(kind) { case QCollection: qualifiedRef(en.module, en.name) + ".values"; case QName: expr(args[0]) + ".label"; case QLookup: qualifiedRef(en.module, EnumQueryExpander.lowerFirst(en.name) + "OfName") + "(" + expr(args[1]) + ")"; };
	}

	/**
		A list literal: an empty one carries its element type because Dart
		infers the empty literal as the dynamic list otherwise; non-empty
		literals infer from their elements.
	**/
	function arrayLiteral(e: TypedExpr, elems: Array<TypedExpr>): String {
		if(elems.length == 0) {
			final elem = switch(Context.follow(e.t)) {
				case TInst(_, params) if(params.length > 0): types.of(params[0]);
				case _: "dynamic";
			};
			return "<" + elem + ">[]";
		}
		return "[" + [for(x in elems) expr(x)].join(", ") + "]";
	}

	function functionLiteral(f: TFunc): String {
		final required: Array<String> = [];
		final optional: Array<String> = [];
		var optionalStarted = false;
		for(a in f.args) {
			final coalescing = currentLocalName != null && currentClass != null && currentField != null
				&& DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, a.v.name) != null;
			if(coalescing) optionalStarted = true;
			final part = types.of(a.v.t) + " " + a.v.name;
			if(optionalStarted) optional.push(part) else required.push(part);
		}
		final paramGroups = required.copy();
		if(optional.length > 0) paramGroups.push("[" + optional.join(", ") + "]");
		final params = paramGroups.join(", ");
		final bodyStmts = statementsOf(f.expr);
		if(bodyStmts.length == 1) {
			switch(bodyStmts[0].expr) {
				case TReturn(r) if(r != null):
					return "(" + params + ") => " + expr(r);
				case _:
			}
		}
		return "(" + params + ") {\n" + blockLines(bodyStmts, 1).join("\n") + "\n}";
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
				if(isStringTyped(e)) {
					return templateLiteral(l, r);
				}
				return operand(l, op, false) + " + " + operand(r, op, true);
			case OpDiv:
				// Dart `/` on two ints yields the double division Haxe
				// `/` yields; no widening runs on either side.
				return operand(l, op, false) + " / " + operand(r, op, true);
			case OpShl:
				// The i32 domain of features/14: Dart's int is a 64-bit
				// word, so a shifted value can leave the domain the
				// source's Int promises; the result re-signs into it.
				return "(" + operand(l, op, false) + " << " + operand(r, op, true) + ").toSigned(32)";
			case OpUShr:
				// The unsigned shift reads its left side as u32 and the
				// result re-signs into i32, the wrap targets with a
				// native 32-bit int perform in hardware.
				return "(" + operand(l, op, false) + ".toUnsigned(32) >> " + operand(r, op, true) + ").toSigned(32)";
			case _:
				return operand(l, op, false) + " " + symbolOf(op) + " " + operand(r, op, true);
		}
	}

	/**
		Parenthesization under Dart's own precedence table: a child below
		the parent's tier wraps, and an equal-tier right child wraps
		unless the same associative operator chains.
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
			case OpIncrement: return post ? wrapped + "++" : "++" + wrapped;
			case OpDecrement: return post ? wrapped + "--" : "--" + wrapped;
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
				final cls = c.get();
				// A private static lowers under its `_`-prefixed Dart
				// name (feature spec 27); Haxe keeps private statics
				// inside their module, so the reference stays
				// same-library.
				final ownerModule = cls.module != "" ? cls.module : (cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name);
				return staticRef(cls, memberName(ownerModule, cf, subj.pos));
			case FEnum(en, ef):
				// A construct without payload in value position: the
				// generated subclass instance carries the identity.
				final enumDef = en.get();
				imports.type(enumDef.module, enumDef.name);
				return isValueEnum(enumDef)
					? qualifiedRef(enumDef.module, enumDef.name) + "." + DartDecl.lowerFirst(ef.name)
					: qualifiedRef(enumDef.module, DartDecl.constructClassName(enumDef.name, ef.name)) + "()";
			case FInstance(owner, _, cf):
				final name = cf.get().name;
				final target = stripCast(subj);
				if(isCatchMessageAccess(target, name)) {
					return expr(target) + ".message";
				}
				// A private member renders under its `_`-prefixed Dart
				// name (feature spec 27). String length is the UTF-16
				// unit count natively; list length and the lowered
				// buffer carry `.length` alike.
				return receiverText(subj) + "." + memberName(owner.get().module, cf, subj.pos);
			case FAnon(cf):
				final name = cf.get().name;
				final target = stripCast(subj);
				if(isCatchMessageAccess(target, name)) {
					return expr(target) + ".message";
				}
				// String length is the UTF-16 unit count natively; list
				// length and the lowered buffer carry `.length` alike.
				return receiverText(subj) + "." + name;
			case FDynamic(name):
				if((name == "length" || name == "get_length") && isStringBuf(subj)) {
					return expr(subj) + ".length";
				}
				return fail(subj, "dynamic field access has no lowering: " + name);
			case FClosure(_):
				return fail(subj, "function value has no lowering (V08)");
		}
	}

	/**
		The reference a top-level name of another module renders under:
		the module's import prefix, or nothing when the declaration sits
		in this same library.
	**/
	function qualifiedRef(module: String, name: String): String {
		final prefix = imports.value(module, name);
		return prefix.length > 0 ? prefix + "." + name : name;
	}

	function staticRef(cls: ClassType, name: String): String {
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) {
			return qualifiedRef(cls.module, valueType.name) + "." + name;
		}
		final markedField = findStaticField(cls, name);
		if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
			final nativeName = markedField.isPublic ? name : "_" + name;
			return qualifiedRef(cls.module, nativeName);
		}
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		final module = cls.module != "" ? cls.module : path;
		switch(module) {
			case "Math":
				// The stdlib members map onto the core members and
				// dart:math; the call sites lower the functional ones.
				if(name == "NaN") return "double.nan";
				if(name == "POSITIVE_INFINITY") return "double.infinity";
				if(name == "NEGATIVE_INFINITY") return "double.negativeInfinity";
				return fail(null, "Math." + name + " has no direct Dart lowering; the call site lowers it");
			case "String":
				if(name == "fromCharCode") {
					return fail(null, "String.fromCharCode lowers at its call site");
				}
				return "String." + name;
			case "Std":
				return fail(null, "Std." + name + " lowers at its call site");
			case "haxe.io.FPHelper":
				// stdlib/05: the bit conversions live in the runtime library.
				return runtimeQualified(name);
			case "std.Test" | "std.__test_shim":
				return fail(null, "std.Test." + name + " lowers at its call site");
			case "std.UStringRT":
				return runtimeQualified("UString." + name);
			case "std.Graphemes":
				return runtimeQualified("Graphemes." + name);
			case "std.SortedMap":
				// The sorted resident owns the factory functions; the
				// extern's `builder` maps onto the map flavor.
				return runtimeQualified("SortedTable." + (name == "builder" ? "mapBuilder" : name));
			case "std.SortedSet":
				return runtimeQualified("SortedTable." + (name == "builder" ? "setBuilder" : name));
			case _:
				if(isStaticsOnlyClass(cls) && !RuntimeResidents.isResident(module)) {
					// A statics-only business class lowers to top-level
					// functions of its own library; the reference carries no
					// class. Resident statics keep the class: the runtime
					// library merges several modules whose top-level
					// function names would collide.
					return qualifiedRef(module, name);
				}
				final prefix = imports.value(module, cls.name);
				final head = prefix.length > 0 ? prefix + "." + cls.name : cls.name;
				return head + "." + name;
		}
	}

	function findStaticField(cls: ClassType, name: String): Null<ClassField> {
		for(field in cls.statics.get()) {
			if(field.name == name) return field;
		}
		return null;
	}

	/**
		Whether a class lowers to top-level functions: no instance
		members and no constructor at all (constructors live among the
		statics, so the ctor check covers the instantiated classes).
	**/
	public static function isStaticsOnlyClass(cls: ClassType): Bool {
		if(cls.isInterface || cls.superClass != null || cls.interfaces.length > 0) {
			return false;
		}
		if(cls.constructor != null) {
			return false;
		}
		if(cls.fields.get().length > 0) {
			return false;
		}
		for(sf in cls.statics.get()) {
			if(sf.name == "new") {
				return false;
			}
		}
		return true;
	}

	function typeExpr(t: ModuleType): String {
		switch(t) {
			case TClassDecl(c):
				final cls = c.get();
				return qualifiedRef(cls.module, cls.name);
			case TEnumDecl(en):
				final enumDef = en.get();
				return qualifiedRef(enumDef.module, enumDef.name);
			case _:
				Context.error("type expression has no value lowering", Context.currentPos());
				return null;
		}
	}

	/**
		Call arguments unwrap optionals when the parameter demands a
		plain value: Haxe flows Null<T> into T implicitly (a null
		reaching the callee traps there), while Dart needs the explicit
		unwrap. Optional parameters and untyped parameters keep the
		argument as rendered.
	**/
	function argTexts(fn: TypedExpr, args: Array<TypedExpr>): Array<String> {
		final paramTypes: Array<Null<Type>> = switch(fn.expr) {
			case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
				switch(cf.get().type) {
					case TFun(fargs, _): [for(a in fargs) a.t];
					case _: [for(_ in args) null];
				}
			case _:
				[for(_ in args) null];
		};
		return [
			for(i in 0...args.length) {
				final a = args[i];
				final pt = i < paramTypes.length ? paramTypes[i] : null;
				final demandsValue = pt != null && !isNullLeafType(pt);
				demandsValue && optionalValued(a) ? expr(a) + "!" : expr(a);
			}
		];
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
				'(() { final sb = StringBuffer("["); final n = ${value}.length; var ${index} = 0; while (${index} < n) { if (${index} > 0) { sb.write(", "); } sb.write(${item}); ${index} += 1; } sb.write("]"); return sb.toString(); })()';
			case TInst(c, _) if(StaticFieldHelper.hasSelfConstructionStatic(c.get()) || c.get().meta.has(":dataClass")): value + ".toString()";
			case TAbstract(a, _) if(ValueTypeSupport.isMarkedAbstract(a.get())):
			ValueTypeSupport.memberField(a.get(), "toString") != null
				? value + ".toStringValue()"
				: value + "." + ValueTypeSupport.representationFieldName(a.get()) + ".toString()";
			case TAbstract(a, _) if(a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool"): inConcat && depth == 0 ? value : "'${" + value + "}'";
			case TAbstract(a, params) if(a.get().module == "std.ReadOnlyArray"):
				stdStringType(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, inConcat, origin, depth);
			case TEnum(en, _) if(isParameterlessEnum(en.get())): value + ".label";
			case TEnum(en, _): enumLabeledText(en.get(), value, origin);
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

	/**
		A payload enum operand renders the labeled constructor form of
		features/34 ruling 2: an immediately-invoked closure switching
		over the generated subclasses, the exhaustive enum subject form
		of features/01 with no default arm. A payload arm binds the
		parameter names and interpolates each argument through its
		operand form; a parameterless arm returns the constructor name.
	**/
	function enumLabeledText(en: EnumType, value: String, origin: TypedExpr): String {
		final constructs = [for(ef in en.constructs) ef];
		constructs.sort((a, b) -> Reflect.compare(a.index, b.index));
		final arms: Array<String> = [];
		for(ef in constructs) {
			final args = switch(ef.type) {
				case TFun(args, _): args;
				case _: [];
			};
			final cls = DartDecl.constructClassName(en.name, ef.name);
			final pattern = qualifiedRef(en.module, cls) + (args.length > 0
				? "(" + [for(arg in args) arg.name + ": var " + arg.name].join(", ") + ")"
				: "()");
			if(args.length == 0) {
				arms.push("case " + pattern + ": return \"" + ef.name + "\";");
				continue;
			}
			final parts = [];
			for(i in 0...args.length) {
				parts.push(args[i].name + "=${" + stdStringType(args[i].t, args[i].name, true, origin) + "}");
			}
			arms.push("case " + pattern + ": return \"" + ef.name + "(" + parts.join(", ") + ")\";");
		}
		return '(() { switch (${value}) { ${arms.join(" ")} } })()';
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
		final hex = valueText + ".toRadixString(16).toUpperCase()";
		return digits == null ? hex : hex + ".padLeft(" + expr(digits) + ", \"0\")";
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

	/** Routes calls on a marked abstract implementation to extension members. */
	function valueTypeCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
		switch(stripWrap(fn).expr) {
			case TField(_, FStatic(c, cf)):
				final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
				if(abs == null) return null;
				final field = cf.get();
				if(field.name == "_new") {
					if(args.length == 0) return qualifiedRef(c.get().module, abs.name) + "()";
					return ValueTypeSupport.constructorThrows(abs)
						? qualifiedRef(c.get().module, ValueTypeSupport.constructorName(abs)) + "(" + expr(args[0]) + ")"
						: qualifiedRef(c.get().module, abs.name) + "(" + expr(args[0]) + ")";
				}
				if(field.name == "toString" && args.length > 0) return expr(args[0]) + ".toStringValue()";
				final op = ValueTypeSupport.operatorOf(abs, field);
				if(op != null) {
					return switch(op) {
						case Binary(_): args.length >= 2 ? expr(args[0]) + " " + opStrForValue(op) + " " + expr(args[1]) : qualifiedRef(c.get().module, abs.name);
						case Unary(_): args.length > 0 ? "-" + expr(args[0]) : qualifiedRef(c.get().module, abs.name);
					};
				}
				if(ValueTypeSupport.hasReceiver(field) && args.length > 0) {
					return expr(args[0]) + "." + field.name + "(" + [for(i in 1...args.length) expr(args[i])].join(", ") + ")";
				}
				return qualifiedRef(c.get().module, abs.name) + "." + field.name + "(" + [for(a in args) expr(a)].join(", ") + ")";
			case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
				final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
				if(abs == null) return null;
				final name = cf.get().name == "toString" ? "toStringValue" : cf.get().name;
				return expr(subj) + "." + name + "(" + [for(a in args) expr(a)].join(", ") + ")";
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
		final wrapperCall = valueTypeCall(fn, args);
		if(wrapperCall != null) return wrapperCall;
		final inlineMapCall = mapHasOwnPropertyCall(fn, args);
		if(inlineMapCall != null) {
			return inlineMapCall;
		}
		final renderedArgs = argTexts(fn, args);
		final rendered = renderedArgs.join(", ");
		switch(fn.expr) {
			case TField(_, FStatic(c, cf)) if(c.get().module == "Std" && cf.get().name == "isOfType" && args.length == 2):
				return stdIsOfType(args);
			case TField(subj, FInstance(_, _, cf)) if(cf.get().name == "get_message" && args.length == 0):
				// Property getter on an exception: the native message
				// field (features/06: messages are display text).
				return receiverText(subj) + ".message";
			case TField(subj, FStatic(c, cf)):
				final cls = c.get();
				final fName = cf.get().name;
				final module = cls.module != "" ? cls.module : (cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name);
				if(cls.pack.length == 0 && cls.name == "StringTools" && fName == "hex") {
					return stringToolsHex(args);
				}
				if(cls.pack.length == 0 && cls.name == "StringTools" && fName == "trim") {
					return expr(args[0]) + ".trim()";
				}
				final markedField = findStaticField(cls, fName);
				if(markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
					final nativeName = markedField.isPublic ? fName : "_" + fName;
					if(StaticFunctionMarkers.isExtension(markedField)) {
						if(markedField.isPublic) {
							imports.useExtension(module);
						}
						return renderedArgs[0] + "." + nativeName + "(" + renderedArgs.slice(1).join(", ") + ")";
					}
					return qualifiedRef(module, nativeName) + "(" + rendered + ")";
				}
				if(module == "std.UStringPlatform") {
					return ustringPlatformCall(fName, args, fn);
				}
				if(module == "std.TestPlatform") {
					return testPlatformCall(fName, args, fn);
				}
				if(module == "std.UStringRT") {
					return runtimeQualified("UString." + fName) + "(" + rendered + ")";
				}
				if(module == "std.Graphemes") {
					return runtimeQualified("Graphemes." + fName) + "(" + rendered + ")";
				}
				if(module == "Math") {
					// Members with no bare-function form lower onto the
					// core member of the argument.
					switch(fName) {
						case "floor": return "(" + expr(args[0]) + ").floor()";
						case "ceil": return "(" + expr(args[0]) + ").ceil()";
						case "sqrt":
							imports.useDartMath();
							return "math.sqrt(" + expr(args[0]) + ")";
						case "isNaN": return "(" + expr(args[0]) + ").isNaN";
						case "isFinite": return "(" + expr(args[0]) + ").isFinite";
						case _:
					}
				}
				if(module == "String" && cls.pack.length == 0 && fName == "fromCharCode") {
					// Dart's factory encodes a supplementary scalar as its
					// pair, the Haxe semantics for the valid domain.
					return "String.fromCharCode(" + expr(args[0]) + ")";
				}
				if(module == "Std") {
					final s = expr(args[0]);
					if(fName == "parseFloat") return "(() { final s = " + s + "; var a = 0, b = s.length; bool sp(String c) => c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r'; while (a < b && sp(s[a])) a++; while (b > a && sp(s[b - 1])) b--; final t = s.substring(a, b); var i = 0; if (i < t.length && (t[i] == '+' || t[i] == '-')) i++; var before = 0; while (i < t.length && t.codeUnitAt(i) >= 48 && t.codeUnitAt(i) <= 57) { i++; before++; }; var after = 0; if (i < t.length && t[i] == '.') { i++; while (i < t.length && t.codeUnitAt(i) >= 48 && t.codeUnitAt(i) <= 57) { i++; after++; } }; if (before == 0 && after == 0) return double.nan; if (i < t.length && (t[i] == 'e' || t[i] == 'E')) { i++; if (i < t.length && (t[i] == '+' || t[i] == '-')) i++; final start = i; while (i < t.length && t.codeUnitAt(i) >= 48 && t.codeUnitAt(i) <= 57) i++; if (i == start) return double.nan; }; return i == t.length ? (double.tryParse(t) ?? double.nan) : double.nan; })()";
					if(fName == "parseInt") return "(() { final s = " + s + "; var a = 0, b = s.length; bool sp(String c) => c == ' ' || c == '\\t' || c == '\\n' || c == '\\v' || c == '\\f' || c == '\\r'; while (a < b && sp(s[a])) a++; while (b > a && sp(s[b - 1])) b--; final t = s.substring(a, b); final neg = t.startsWith('-'); final p = (neg || t.startsWith('+')) ? 1 : 0; final d = t.substring(p); final hex = d.startsWith('0x') || d.startsWith('0X'); final q = hex ? d.substring(2) : d; if (q.isEmpty) return null; var i = 0; while (i < q.length && ((q.codeUnitAt(i) >= 48 && q.codeUnitAt(i) <= 57) || (hex && ((q.codeUnitAt(i) >= 65 && q.codeUnitAt(i) <= 70) || (q.codeUnitAt(i) >= 97 && q.codeUnitAt(i) <= 102))))) i++; if (i != q.length) return null; final n = int.tryParse(hex ? q : d, radix: hex ? 16 : 10); if (n == null) return null; final v = neg ? -n : n; return v >= -2147483648 && v <= 2147483647 ? v : null; })()";
					if(fName == "int") {
						final arg = stripWrap(args[0]);
						switch(arg.expr) {
							case TBinop(OpDiv, l, r) if(isIntTyped(l) && isIntTyped(r)):
								// Truncating division of two Ints.
								return expr(l) + " ~/ " + expr(r);
							case _:
						}
						return "(" + expr(args[0]) + ").truncate()";
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
					// The factory fixes only the comparator's key, so the
					// value argument cannot infer; the call spells both.
					return runtimeQualified("SortedTable.mapBuilder") + "<" + types.of(kTypeOf(fn)) + ", " + types.of(vTypeOf(fn)) + ">(" + sortedComparator(kTypeOf(fn), fn.pos) + ")";
				}
				if(module == "std.SortedSet" && fName == "builder") {
					return runtimeQualified("SortedTable.setBuilder") + "<" + types.of(kTypeOf(fn)) + ">(" + sortedComparator(kTypeOf(fn), fn.pos) + ")";
				}
			case _:
		}
		switch(fn.expr) {
			case TCast(inner, _):
				return call(inner, args);
			case TField(subj, FDynamic(name)) if((name == "length" || name == "get_length") && isStringBuf(subj)):
				return expr(subj) + ".length";
			case TField(subj, FInstance(owner, _, cf)):
				final name = cf.get().name;
				if(isStringSubject(subj)) {
					if(name == "toLowerCase") return expr(subj) + ".toLowerCase()";
					if(name == "toUpperCase") return expr(subj) + ".toUpperCase()";
				}
				if(isMapType(subj.t)) {
					if(name == "exists" && args.length == 1) return expr(subj) + ".containsKey(" + expr(args[0]) + ")";
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
				// stdlib/01: Bytes.get(i) is a plain index read of the
				// lowered list.
				if(name == "get" && isBytes(stripCast(subj).t)) {
					return receiverText(subj) + "[" + expr(args[0]) + "]";
				}
				// stdlib/02: the growable byte sink is the plain int
				// list; addByte appends one element.
				if(name == "addByte" && isBytesBuffer(stripCast(subj).t)) {
					return receiverText(subj) + ".add(" + expr(args[0]) + ")";
				}
				if(name == "getBytes" && isBytesBuffer(stripCast(subj).t)) {
					// The buffer lowers to the list itself; the view of
					// getBytes is the identical reference.
					return receiverText(subj);
				}
				if(name == "push") {
					return receiverText(subj) + ".add(" + rendered + ")";
				}
				if(name == "join") {
					return receiverText(subj) + ".join(" + rendered + ")";
				}
				if(name == "slice") {
					return receiverText(subj) + ".sublist(" + expr(args[0]) + ", " + expr(args[1]) + ")";
				}
				if(name == "substring" && isStringSubject(subj)) {
					// The haxe typer passes a synthesized null for an
					// omitted ?endIndex; the native suffix overload
					// carries the one-argument cut.
					final endOmitted = args.length < 2 || switch(stripWrap(args[1]).expr) {
						case TConst(TNull): true;
						case _: false;
					};
					return endOmitted
						? receiverText(subj) + ".substring(" + expr(args[0]) + ")"
						: receiverText(subj) + ".substring(" + expr(args[0]) + ", " + expr(args[1]) + ")";
				}
				if(name == "charCodeAt" && isStringSubject(subj)) {
					return receiverText(subj) + ".codeUnitAt(" + expr(args[0]) + ")";
				}
				// A private method renders under its `_`-prefixed Dart
				// name (feature spec 27); the special cases above are
				// public library APIs.
				return receiverText(subj) + "." + memberName(owner.get().module, cf, subj.pos) + "(" + rendered + ")";
			case TField(_, FEnum(en, ef)):
				return enumConstruct(en.get(), ef, args);
			case TConst(TSuper):
				// Constructors lower through constructorParts; this arm
				// only serves the analysis fallback.
				return "super(" + rendered + ")";
			case _:
				return expr(fn) + "(" + rendered + ")";
		}
	}

	/** A runtime-library top-level or class-static reference with its prefix. */
	function runtimeQualified(name: String): String {
		final prefix = imports.runtimePrefix();
		return prefix.length > 0 ? prefix + "." + name : name;
	}

	/**
		Cursor primitives of the resident UString walk, inlined per call
		against the native string: end is the unit count, codeAt is the
		pair-combining codePointAt, advance adds the surrogate-pair
		width, and fromCodePoint guards the valid domain (an
		out-of-domain argument yields the NUL replacement, matching the
		other lanes). Business code never reaches these; it calls
		std.UString.
	**/
	function ustringPlatformCall(fName: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		if(!imports.selfResident) {
			Context.error("std.UStringPlatform is a resident runtime primitive; business code calls std.UString", fn.pos);
		}
		switch(fName) {
			case "end":
				return expr(args[0]) + ".length";
			case "codeAt":
				// The private pair-combining helper of whichever library
				// inlines the walk (the runtime prelude and the test host
				// each carry one).
				return "_codePointAt(" + expr(args[0]) + ", " + expr(args[1]) + ")";
			case "advance":
				final s = expr(args[0]);
				final i = expr(args[1]);
				return "(" + i + " + (_codePointAt(" + s + ", " + i + ") > 65535 ? 2 : 1))";
			case "substringBetween":
				return expr(args[0]) + ".substring(" + expr(args[1]) + ", " + expr(args[2]) + ")";
			case "fromCodePoint":
				final cp = expr(args[0]);
				return "((" + cp + " >= 0 && " + cp + " <= 1114111 && !(" + cp + " >= 55296 && " + cp + " <= 57343)) ? String.fromCharCode(" + cp + ") : String.fromCharCode(0))";
			case _:
				return fail(fn, "UStringPlatform." + fName + " has no Dart lowering");
		}
	}

	/**
		Host edges of the resident runtime.TestCore, inlined per call:
		raising is a throw of the host failure type, the running test id
		lives in the private top-level state of the test host library
		(this same library TestCore appends into), and plain numbers
		render through toString. Business code never reaches these; it
		calls std.Test.
	**/
	function testPlatformCall(fName: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		if(!RuntimeResidents.isTestResident(imports.selfModule)) {
			Context.error("std.TestPlatform is a resident runtime primitive; business code calls std.Test", fn.pos);
		}
		switch(fName) {
			case "raise":
				return "throw TestFailure(" + expr(args[0]) + ")";
			case "currentTestId":
				return "_currentTestId";
			case "intToString":
				return "(" + expr(args[0]) + ").toString()";
			case "floatToString":
				return "(" + expr(args[0]) + ").toString()";
			case _:
				return fail(fn, "TestPlatform." + fName + " has no Dart lowering");
		}
	}

	/**
		std.Test assertions: scalars route to the TestCore checks with
		the message passed natively; composite values route to the
		generated assertion of their tag (features/19).
	**/
	function testCall(fName: String, args: Array<TypedExpr>, fn: TypedExpr): String {
		final host = imports.runtimeTestPrefix();
		final core = host.length > 0 ? host + ".TestCore" : "TestCore";
		switch(fName) {
			case "ok":
				return core + ".ok(" + expr(args[0]) + ", " + testMessageText(args, 1) + ")";
			case "fail":
				return core + ".fail(" + testMessageText(args, 0) + ")";
			case "equals":
				// The assertion type comes from the actual value: the
				// expected side may be the bare null literal, and
				// following it would unwrap the optionality the route
				// needs to see.
				final t = equalsAssertType(args);
				final message = testMessageText(args, 2);
				if(DartTestTypes.isScalarRoute(t)) {
					return switch(t) {
						case TAbstract(a, _) if(a.get().name == "Int"): core + ".equalsInt(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case TAbstract(a, _) if(a.get().name == "Float"): core + ".equalsFloat(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case TAbstract(a, _) if(a.get().name == "Bool"): core + ".equalsBool(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case TInst(c, _) if(c.get().name == "String"):
							core + ".equalsString(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
						case _: fail(fn, "test assertion type has no Dart lowering");
					};
				}
				final tag = DartTestTypes.register(t);
				return "test_helper.assertEquals" + tag + "(" + expr(args[0]) + ", " + expr(args[1]) + ", " + message + ")";
			case _:
				return fail(fn, "std.Test." + fName + " has no Dart lowering");
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

	/** The message argument as the native string; null renders empty. */
	function testMessageText(args: Array<TypedExpr>, index: Int): String {
		if(args.length <= index) {
			return "''";
		}
		final m = args[index];
		switch(stripWrap(m).expr) {
			case TConst(TNull): return "''";
			case _:
		}
		return switch(Context.follow(m.t)) {
			case TAbstract(a, _) if(a.get().name == "Null"): "(" + expr(m) + " ?? '')";
			case _: expr(m);
		};
	}

	/**
		The one pipeline call the expander leaves in place: sorting by a
		key function. The comparator closure binds the key expressions
		under the expander's parameter names; string keys compare
		through compareTo because native String order is the UTF-16 unit
		order stdlib/07 rules for keys, and integer keys use the same
		numerator. The sort itself is a copy-then-sort cascade: the
		cascade evaluates to the sorted copy.
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
			final comparator = isStringLeafType(bodyExpr.t) || isIntLeafType(bodyExpr.t)
				? keyA + ".compareTo(" + keyB + ")"
				: "compare" + structKeyTagName(bodyExpr.t) + "(" + keyA + ", " + keyB + ") < 0";
			return "[..." + expr(receiver) + "]..sort((_a, _b) => " + comparator + ")";
		}
		return fail(fn, "sortedBy requires a single-parameter key function");
	}

	/** The record name a structure key carries, per the shape registry. */
	function structKeyTagName(t: Null<Type>): String {
		return switch(Context.follow(t)) {
			case TType(d, _): d.get().name;
			case TAnonymous(anon):
				final def = DartDecl.structTypedefs.get(DartDecl.structureSignature(anon));
				if(def == null) {
					Context.error("sortedBy key literal must match a named structure typedef", Context.currentPos());
				}
				def.get().name;
			case _: Context.error("sortedBy structure key has no Dart lowering", Context.currentPos());
		};
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
		the unit-order helper of the runtime prelude (native compareTo
		wrapped for the tear-off shape), structures take the per-type
		generated comparison.
	**/
	function sortedComparator(kType: Null<Type>, pos: haxe.macro.Expr.Position): String {
		if(kType == null) {
			Context.error("sorted builder requires an explicit key type", pos);
		}
		return switch(DartType.classifyKey(kType, pos)) {
			case DartIntKey:
				runtimeQualified("SortedTable.compareInts");
			case DartStringKey:
				runtimeQualified("compareUnitOrder");
			case DartStructKey(def, _):
				final cmpName = "compare" + def.name;
				qualifiedRef(def.module, cmpName);
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

	/** A variant construct renders as its generated subclass constructor, arguments positional. */
	function enumConstruct(enumDef: EnumType, ef: EnumField, args: Array<TypedExpr>): String {
		if(isValueEnum(enumDef)) return qualifiedRef(enumDef.module, enumDef.name) + "." + DartDecl.lowerFirst(ef.name);
		final parts = [for(a in args) expr(a)];
		final cls = DartDecl.constructClassName(enumDef.name, ef.name);
		return qualifiedRef(enumDef.module, cls) + "(" + parts.join(", ") + ")";
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
		final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
		if(valueType != null) {
			return ValueTypeSupport.constructorThrows(valueType)
				? qualifiedRef(cls.module, ValueTypeSupport.constructorName(valueType)) + "(" + rendered + ")"
				: qualifiedRef(cls.module, valueType.name) + "(" + rendered + ")";
		}
		final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
		switch(path) {
			case "std.StringBuf" | "StringBuf":
				return "<int>[]";
			case "haxe.ds._Map.Map_Impl_":
				return "Map()";
			case "haxe.io.BytesBuffer":
				// The growable byte sink is the plain int list.
				return "<int>[]";
			case "Array":
				return "<" + types.of(params[0]) + ">[]";
			case _:
				// The type arguments ride on the constructor so the call
				// needs no inference to bind them.
				final head = qualifiedRef(cls.module, cls.name);
				return (params.length > 0 ? head + "<" + [for(p in params) types.of(p)].join(", ") + ">" : head) + "(" + rendered + ")";
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
			case TField(subj, FInstance(owner, _, cf)):
				// A private field assigns through its `_`-prefixed Dart
				// name (feature spec 27).
				return expr(subj) + "." + memberName(owner.get().module, cf, e.pos);
			case TField(subj, FAnon(cf)):
				return expr(subj) + "." + cf.get().name;
			case TLocal(v):
				return localName(v);
			case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
				return assignTarget(inner);
			case _:
				return fail(e, "assignment target has no Dart lowering");
		}
	}

	/**
		A record literal renders as the positional constructor of its
		named class, with the parts reordered to the declaration order
		the constructor takes. The typer leaves the literal's own type
		anonymous even where unification matched the typedef, so the
		class resolves through the shape registry when the expression
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
			parts.push(expr(value));
		}
		final prefix = imports.type(def.module, def.name);
		return (prefix.length > 0 ? prefix + "." + def.name : def.name) + "(" + parts.join(", ") + ")";
	}

	/** The named record behind a literal's type: direct when named, by shape when the typer kept it anonymous. */
	function resolveRecordDef(t: Null<Type>): Null<DefType> {
		if(t == null) {
			return null;
		}
		return switch(Context.follow(t)) {
			case TType(d, _): d.get();
			case TAnonymous(anon):
				final def = DartDecl.structTypedefs.get(DartDecl.structureSignature(anon));
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
		Try regions lower as native try/on with typed catch arms. An
		`on` clause only catches its own domain, so unmatched
		exceptions propagate with no rethrow footer, and no call-site
		marking exists on this lane. The arm binds the error only when
		the handler reads it.
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

	/** The emitted class name behind the catch arm, with its reference registered. */
	function exceptionClassOf(c: {v: TVar, expr: TypedExpr}): Null<String> {
		return switch(Context.follow(c.v.t)) {
			case TInst(cls, _):
				qualifiedRef(cls.get().module, cls.get().name);
			case _: null;
		};
	}

	/** Whether the handler reads the caught variable. */
	function handlerBindsError(c: {v: TVar, expr: TypedExpr}): Bool {
		return mentionsLocal(c.expr, c.v);
	}

	/**
		Splits a region body or handler into its leading statements and
		its trailing value expression; control-flow tails carry no value.
	**/
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
				return {lines: lines.concat(checks), value: "String.fromCharCodes(" + expr(subj) + ")"};
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
			return indent(depth) + "} on " + clsName + " catch (" + localName(c.v) + ") {";
		}
		return indent(depth) + "} on " + clsName + " {";
	}

	/** Statement-position region: the handler runs as a block. */
	function tryStatementLines(body: TypedExpr, c: {v: TVar, expr: TypedExpr}, depth: Int): Array<String> {
		final clsName = exceptionClassOf(c);
		if(clsName == null) {
			return fail(c.expr, "try region catch type is not an exception class");
		}
		final out = [indent(depth) + "try {"];
		for(l in blockLines(statementsOf(body), depth + 1)) out.push(l);
		out.push(catchHeaderLine(c, clsName, depth));
		catchVars.set(c.v.id, true);
		final handler = blockLines(statementsOf(c.expr), depth + 1);
		catchVars.remove(c.v.id);
		for(l in handler) out.push(l);
		out.push(indent(depth) + "}");
		return out;
	}

	/**
		Initializer-position region: definite assignment binds the local
		through both arms. The declaration carries the type because it
		has no initializer to infer from.
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
		final out = [
			indent(depth) + types.of(v.t) + " " + name,
			indent(depth) + "try {"
		];
		final body = blockValueLines(parts.body, depth + 1);
		if(body.value == null) {
			return fail(region, "try region body has no value");
		}
		for(l in body.lines) out.push(l);
		if(!armPrefixThrows(parts.body)) {
			out.push(indent(depth + 1) + name + " = " + body.value);
		}
		out.push(catchHeaderLine(parts.c, clsName, depth));
		catchVars.set(parts.c.v.id, true);
		final handler = blockValueLines(parts.c.expr, depth + 1);
		catchVars.remove(parts.c.v.id);
		if(handler.value == null) {
			return fail(parts.c.expr, "try region handler has no value");
		}
		for(l in handler.lines) out.push(l);
		if(!armPrefixThrows(parts.c.expr)) {
			out.push(indent(depth + 1) + name + " = " + handler.value);
		}
		out.push(indent(depth) + "}");
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
		if(!armPrefixThrows(parts.body)) {
			out.push(indent(depth + 1) + "return " + body.value);
		}
		out.push(catchHeaderLine(parts.c, clsName, depth));
		catchVars.set(parts.c.v.id, true);
		final handler = blockValueLines(parts.c.expr, depth + 1);
		catchVars.remove(parts.c.v.id);
		if(handler.value == null) {
			return fail(parts.c.expr, "try region handler has no value");
		}
		for(l in handler.lines) out.push(l);
		if(!armPrefixThrows(parts.c.expr)) {
			out.push(indent(depth + 1) + "return " + handler.value);
		}
		out.push(indent(depth) + "}");
		return out;
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

	// ------------------------------------------------------------------
	// String buffer checks (stdlib/08)
	// ------------------------------------------------------------------

	/**
		stdlib/08 string-buffer checks (Dart): the buffer is the int list
		of its UTF-16 units, every checked operation reads the trailing
		unit through a list index, and the fault constructs the compiled
		std.UStringException with the UnpairedSurrogate variant. A throw
		is a statement here, so the checked operations lower at
		statement, binding, or return position only. An empty buffer
		holds no trailing unit; -1 fails every range check the way the
		NaN tail read of the TS lane does.
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
		};
	}

	function freshTailName(): String {
		stringBufTailCounter += 1;
		return stringBufTailCounter == 1 ? "tail" : "tail" + stringBufTailCounter;
	}

	/** The trailing-unit read every check opens with. */
	function stringBufTailLines(subj: TypedExpr, depth: Int): {name: String, lines: Array<String>} {
		final name = freshTailName();
		final buf = expr(subj);
		return {
			name: name,
			lines: [indent(depth) + "final " + name + " = " + buf + ".length > 0 ? " + buf + "[" + buf + ".length - 1] : -1"]
		};
	}

	function stringBufFaultThrow(depth: Int, unit: String): String {
		return indent(depth) + "throw " + qualifiedRef("std.UStringException", "UStringException") + "("
			+ qualifiedRef("std.UStringFault", DartDecl.constructClassName("UStringFault", "UnpairedSurrogate")) + "(" + unit + "))";
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
			// stays paired: only the unpaired case faults. codeUnits is
			// the unit view of the native string; the argument
			// expressions are pure (locals, parameters, literals).
			lines.push(indent(depth) + "if (" + tail + " >= 55296 && " + tail + " <= 56319 && !(" + part + ".length > 0 && " + part + ".codeUnitAt(0) >= 56320 && " + part + ".codeUnitAt(0) <= 57343)) {");
			lines.push(stringBufFaultThrow(depth + 1, tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + ".addAll(" + part + ".codeUnits)");
		} else {
			final u = expr(args[0]);
			lines.push(indent(depth) + "if (" + u + " >= 56320 && " + u + " <= 57343) {");
			lines.push(indent(depth + 1) + "if (!(" + tail + " >= 55296 && " + tail + " <= 56319)) {");
			lines.push(stringBufFaultThrow(depth + 2, u));
			lines.push(indent(depth + 1) + "}");
			lines.push(indent(depth) + "} else if (" + tail + " >= 55296 && " + tail + " <= 56319) {");
			lines.push(stringBufFaultThrow(depth + 1, tail));
			lines.push(indent(depth) + "}");
			lines.push(indent(depth) + buf + ".add(" + u + ")");
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
		final kw = mutated.exists(v.id) ? "var" : "final";
		lines.push(indent(depth) + kw + " " + localName(v) + " = String.fromCharCodes(" + expr(subj) + ")");
		return lines;
	}

	function stringBufToStringReturnLines(call: TypedExpr, depth: Int): Array<String> {
		final subj = stringBufToStringSubject(call);
		final lines = stringBufToStringCheckLines(subj, depth);
		lines.push(indent(depth) + "return String.fromCharCodes(" + expr(subj) + ")");
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
		A variant switch lowers as a switch statement over object
		patterns of the generated subclasses. The arms bind payloads
		through `field: var name` subpatterns; the sealed hierarchy
		keeps the statement exhaustive with no default arm.
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
		final out = [indent(depth) + "switch (" + subjRendered + ") {"];
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
			final bindings = [for(i in 0...names.length) if(used.indexOf(i) >= 0) names[i] + ": var " + names[i]];
			final cls = DartDecl.constructClassName(info.enumName, info.name);
			final pattern = bindings.length == 0 && info.valueEnum
				? qualifiedRef(info.module, info.enumName) + "." + DartDecl.lowerFirst(info.name)
				: qualifiedRef(info.module, cls) + (bindings.length > 0 ? "(" + bindings.join(", ") + ")" : "()");
			out.push(indent(depth + 1) + "case " + pattern + ":");
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
							Context.error("dart target: declaration without initializer has no lowering", s.pos);
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
								out.push(indent(depth) + "final " + localName(v) + " = " + expr(init));
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

	function enumTable(se: TypedExpr): Map<Int, {name: String, field: EnumField, enumName: String, module: String, valueEnum: Bool}> {
		final table = new Map<Int, {name: String, field: EnumField, enumName: String, module: String, valueEnum: Bool}>();
		switch(se.t) {
			case TEnum(e, _):
				final en = e.get();
				for(name => ef in en.constructs) {
					table.set(ef.index, {name: name, field: ef, enumName: en.name, module: en.module, valueEnum: isValueEnum(en)});
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
		Unread positions drop their subpatterns entirely.
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
		Whether a `+` expression produces a string: Dart has no string
		concatenation with numbers, so a non-string leaf renders through
		interpolation instead.
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
		};
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
				// Dart interpolation carries no escape: the braces alone
				// delimit the hole.
				case _:
					final stdArg = stdStringArg(leaf);
					b.add("${" + (stdArg == null ? expr(leaf) : stdString(stdArg, true)) + "}");
			}
		}
		b.addChar('"'.code);
		return b.toString();
	}

	/**
		A flattened leaf: right-nested additions keep no parentheses;
		weaker operators take them. An optional String leaf unwraps: the
		source guards it null before the concatenation (the Haxe typer
		flows the checked value through), and Dart needs the unwrap a
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
						// Storing through an index reads the reference
						// only; the list itself stays final.
						switch(stripWrap(arr).expr) {
							case TLocal(_):
							case _:
						}
					case _:
				}
			case TCall(fn, _):
				switch(fn.expr) {
					case TField(subj, FInstance(_, _, cf)):
						final n = cf.get().name;
						final mutates = (isStringBuf(subj) && (n == "add" || n == "addChar"));
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
		// A bare underscore is not a name Dart binds (the wildcard
		// marker); loop counters written `_` render as `_i`.
		if(v.name == "_") {
			return "_i";
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
			case _: return fail(null, "operator has no Dart lowering");
		}
	}

	/**
		Dart's binary precedence table: multiplication binds tightest,
		then addition, shifts, `&`, `^`, `|`, comparisons, equality, and
		the logical pair.
	**/
	function precedenceOf(op: Binop): Int {
		return switch(op) {
			case OpBoolOr: 1;
			case OpBoolAnd: 2;
			case OpEq | OpNotEq: 3;
			case OpGt | OpGte | OpLt | OpLte: 4;
			case OpOr: 5;
			case OpXor: 6;
			case OpAnd: 7;
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

	function isIntTyped(e: TypedExpr): Bool {
		return isIntLeafType(e.t);
	}

	function isIntLeafType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Int";
			case TLazy(f): isIntLeafType(f());
			case _: false;
		};
	}

	function isBytes(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
			case TType(d, _):
				final def = d.get();
				def.pack.join(".") == "haxe.io" && def.name == "Bytes";
			case TLazy(f): isBytes(f());
			case _: false;
		};
	}

	function isBytesBuffer(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TInst(c, _):
				final cls = c.get();
				cls.pack.join(".") == "haxe.io" && cls.name == "BytesBuffer";
			case TLazy(f): isBytesBuffer(f());
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

	function fieldName(fa: FieldAccess): String {
		return switch(fa) {
			case FInstance(_, _, cf): cf.get().name;
			case FStatic(_, cf): cf.get().name;
			case FAnon(cf): cf.get().name;
			case FDynamic(n): n;
			case FClosure(_, cf): cf.get().name;
			case FEnum(_, ef): ef.name;
		};
	}

	/**
		The Dart name of an instance member (feature spec 27): a private
		member of this library renders with the `_` prefix; a private
		member of another library has no lowering, because Dart privacy
		is library-scoped and the generated tree holds one library per
		module.
	**/
	function memberName(ownerModule: String, cf: Ref<ClassField>, pos: haxe.macro.Expr.Position): String {
		final field = cf.get();
		if(field.isPublic) {
			return field.name;
		}
		if(ownerModule != imports.selfModule) {
			Context.error("private member " + field.name + " of " + ownerModule + " has no Dart lowering outside its library", pos);
		}
		return "_" + field.name;
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
				case 36: b.add('\\$');
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
				case 36: b.add('\\$');
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
			b.add("  ");
		}
		return b.toString();
	}

	function fail(e: Null<TypedExpr>, message: String): Dynamic {
		final pos = e != null ? e.pos : Context.currentPos();
		Context.error("dart target: " + message, pos);
		return null;
	}
}
#end
