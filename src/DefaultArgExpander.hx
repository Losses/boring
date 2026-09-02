#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Constant as AstConstant;
import haxe.macro.Expr.Function as AstFunction;
import haxe.macro.Expr.FunctionKind;
import haxe.macro.Expr.Position;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.EnumField;
import haxe.macro.Type.EnumType;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.ModuleType;
import haxe.macro.Type.Ref;
import haxe.macro.Type.TConstant;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;

enum DefaultArgValue {
	VInt(v:Int);
	VFloat(s:String);
	VString(s:String);
	VBool(b:Bool);
	VNull;
	VEnum(enumRef:Ref<EnumType>, enumField:EnumField);
	VCoalescing(value:CoalescingDefaultValue);
}

/** One registered coalescing site of a function, used by the stage-1 rewrite. */
typedef CoalescingSiteInfo = {name:String, argIdx:Int, value:CoalescingDefaultValue, excluded:Expr, defaultExpr:Expr};

/**
	The deliberately small expression language accepted by a coalescing
	default.  Keeping this separate from DefaultArgValue prevents a
	coalescing expression from being materialized at a call site.
*/
enum CoalescingDefaultValue {
	CInt(v:Int);
	CFloat(s:String);
	CString(s:String);
	CBool(b:Bool);
	CNull;
	CEmptyArray;
	CEmptyMap;
	CPositiveInfinity;
	CNegativeInfinity;
	CEnum(enumRef:Ref<EnumType>, enumField:EnumField);
	CParameterRead(parameterName:String);
	CInstanceFieldRead(fieldName:String);
	CLocalRead(localName:String);
	CFieldAccess(receiver:CoalescingDefaultValue, fieldName:String);
	CMethodCall(receiver:CoalescingDefaultValue, methodName:String, args:Array<CoalescingDefaultValue>);
	CStaticCall(fullPath:String, args:Array<CoalescingDefaultValue>);
	CConditional(condition:CoalescingDefaultValue, ifTrue:CoalescingDefaultValue, ifFalse:CoalescingDefaultValue);
	CBinaryOp(op:Binop, left:CoalescingDefaultValue, right:CoalescingDefaultValue);
	CConstructorCall(classPath:String, args:Array<CoalescingDefaultValue>);
}

/**
 * Default argument expansion pass per docs/specs/features/22-default-argument-expansion.md.
 * Completes omitted trailing arguments at typed call sites with compile-time constants.
 */
class DefaultArgExpander {
	static final fieldDefaults:Map<String, Array<Null<DefaultArgValue>>> = new Map();
	static final fieldDefaultsByName:Map<String, Array<Null<DefaultArgValue>>> = new Map();
	static final fieldCoalescing:Map<String, CoalescingDefaultValue> = new Map();
	static final fieldCoalescingReadsParam:Map<String, Bool> = new Map();
	static final coalescingSourceRanges:Array<{file:String, min:Int, max:Int}> = [];
	static final normalizationSourceRanges:Array<{file:String, min:Int, max:Int}> = [];
	static final fieldNormalization:Map<String, CoalescingDefaultValue> = new Map();
	static final localNormalization:Map<String, CoalescingDefaultValue> = new Map();
	/** Instance fields registered during the build macro, before typed field tables exist. */
	static final registeredInstanceFields:Map<String, Map<String, Bool>> = new Map();
	// Local bindings are only candidates for the Stage-A default-site form
	// when their value is sanctioned.  An ordinary local ternary must remain
	// ordinary Haxe; the target compiler lowers it without any registry action.
	static var suppressGrammarErrors:Bool = false;
	// These are enabled only while validating a normalization binding. They
	// must not enlarge the closed default-argument leaf set.
	static var allowNormalizationBindingLeaves:Bool = false;
	static var normalizationEarlierLocals:Array<String> = [];

	static final localDefaults:Map<String, Array<Null<DefaultArgValue>>> = new Map();
	static final localDefaultsByName:Map<String, Array<Null<DefaultArgValue>>> = new Map();
	static final localCoalescing:Map<String, CoalescingDefaultValue> = new Map();
	static final localCoalescingReadsParam:Map<String, Bool> = new Map();

	/** Registration counts per bare name; a by-name fallback may fire only when the count is exactly one. */
	static final fieldNameCounts:Map<String, Int> = new Map();
	static final localNameCounts:Map<String, Int> = new Map();

	/** Stable identity of a class across the syntax and typed passes. */
	public static function classKeyOf(classType:ClassType):String {
		return getClassKey(classType);
	}

	public static function registerClassFields(classType:ClassType, fields:Array<Field>):Void {
		final classKey = getClassKey(classType);
		final instanceFields:Map<String, Bool> = new Map();
		for (field in fields) {
			if (field.access.indexOf(Access.AStatic) < 0) instanceFields.set(field.name, true);
		}
		registeredInstanceFields.set(classKey, instanceFields);
		for (index in 0...fields.length) {
			final field = fields[index];
			switch (field.kind) {
				case FieldType.FFun(fun):
					final sites:Array<CoalescingSiteInfo> = [];
					final coalescing = discoverCoalescingDefaults(fun.args, fun.expr, classType, sites);
					discoverNormalizationBindings(fun.args, fun.expr, classType, coalescing);
					final defaults:Array<Null<DefaultArgValue>> = [];
					var hasDefault = false;
					for (argIdx in 0...fun.args.length) {
						final arg = fun.args[argIdx];
						if (coalescing[argIdx] != null) {
							final value = coalescing[argIdx];
							defaults.push(VCoalescing(value));
							fieldCoalescing.set(classKey + ":" + field.name + ":" + arg.name, value);
							fieldCoalescingReadsParam.set(classKey + ":" + field.name + ":" + arg.name, readsParameter(value));
							hasDefault = true;
						} else if (arg.value != null) {
							final constructor = constructorDefaultValue(arg.value, classType);
							if (constructor != null) {
								defaults.push(VCoalescing(constructor));
								fieldCoalescing.set(classKey + ":" + field.name + ":" + arg.name, constructor);
								fieldCoalescingReadsParam.set(classKey + ":" + field.name + ":" + arg.name, readsParameter(constructor));
							} else {
								final v = evalConstantExpr(arg.value, classType);
								defaults.push(v);
							}
							hasDefault = true;
						} else if (arg.opt == true) {
							defaults.push(VNull);
							hasDefault = true;
						} else {
							defaults.push(null);
						}
					}
					if (hasDefault) {
						fieldDefaults.set(classKey + ":" + field.name, defaults);
						fieldDefaultsByName.set(field.name, defaults);
						fieldNameCounts.set(field.name, (fieldNameCounts.exists(field.name) ? fieldNameCounts.get(field.name) : 0) + 1);
					}
					if (fun.expr != null) {
						rewriteCrossSiteReads(fun.expr, sites);
						walkLocalFunctions(fun.expr, classType, field.name);
					}
				default:
			}
		}
	}

	static function getClassKey(classType:ClassType):String {
		return (classType.pack.length > 0 ? classType.pack.join(".") + "." : "") + classType.name;
	}

	static function walkLocalFunctions(e:Expr, classType:ClassType, fieldName:String):Void {
		if (e == null) return;
		switch (e.expr) {
			case ExprDef.EFunction(kind, func):
				var fnName:Null<String> = null;
				if (kind != null) {
					switch (kind) {
						case FunctionKind.FNamed(n, _): fnName = n;
						default:
					}
				}
				if (fnName != null) {
					registerLocalFunction(classType, fieldName, fnName, func);
				}
			case ExprDef.EVars(vars):
				for (v in vars) {
					if (v.expr != null) {
						switch (v.expr.expr) {
							case ExprDef.EFunction(_, func):
								registerLocalFunction(classType, fieldName, v.name, func);
							default:
						}
					}
				}
			case ExprDef.EBinop(Binop.OpAssign, lhs, rhs):
				var fnName:Null<String> = null;
				switch (lhs.expr) {
					case ExprDef.EConst(AstConstant.CIdent(n)): fnName = n;
					default:
				}
				if (fnName != null && rhs != null) {
					switch (rhs.expr) {
						case ExprDef.EFunction(_, func):
							registerLocalFunction(classType, fieldName, fnName, func);
						default:
					}
				}
			default:
		}
		haxe.macro.ExprTools.iter(e, child -> walkLocalFunctions(child, classType, fieldName));
	}

	static function registerLocalFunction(classType:ClassType, fieldName:String, fnName:String, func:AstFunction):Void {
		final classKey = getClassKey(classType);
		final sites:Array<CoalescingSiteInfo> = [];
		final coalescing = discoverCoalescingDefaults(func.args, func.expr, classType, sites);
		discoverNormalizationBindings(func.args, func.expr, classType, coalescing);
		final defaults:Array<Null<DefaultArgValue>> = [];
		var hasDefault = false;
		for (argIdx in 0...func.args.length) {
			final arg = func.args[argIdx];
			if (coalescing[argIdx] != null) {
				final value = coalescing[argIdx];
				defaults.push(VCoalescing(value));
				localCoalescing.set(classKey + ":" + fieldName + ":" + fnName + ":" + arg.name, value);
				localCoalescingReadsParam.set(classKey + ":" + fieldName + ":" + fnName + ":" + arg.name, readsParameter(value));
				hasDefault = true;
				} else if (arg.value != null) {
					final constructor = constructorDefaultValue(arg.value, classType);
					if (constructor != null) {
						defaults.push(VCoalescing(constructor));
						localCoalescing.set(classKey + ":" + fieldName + ":" + fnName + ":" + arg.name, constructor);
						localCoalescingReadsParam.set(classKey + ":" + fieldName + ":" + fnName + ":" + arg.name, readsParameter(constructor));
					} else {
						final v = evalConstantExpr(arg.value, classType);
						defaults.push(v);
					} 
					hasDefault = true;
			} else if (arg.opt == true) {
				defaults.push(VNull);
				hasDefault = true;
			} else {
				defaults.push(null);
			}
		}
		if (hasDefault) {
			localDefaults.set(classKey + ":" + fieldName + ":" + fnName, defaults);
			localDefaultsByName.set(fnName, defaults);
			localNameCounts.set(fnName, (localNameCounts.exists(fnName) ? localNameCounts.get(fnName) : 0) + 1);
		}
		rewriteCrossSiteReads(func.expr, sites);
	}
	static function constructorDefaultValue(e:Expr, classType:ClassType):Null<CoalescingDefaultValue> {
		final cur = unwrapExpr(e);
		return switch (cur == null ? null : cur.expr) {
			case ExprDef.ENew(typePath, args):
				final path = typePath.pack.length == 0 ? typePath.name : typePath.pack.join(".") + "." + typePath.name;
				if (!isCompiledStaticType(path)) null else validateArgList(args, "", [], [], classType) == null ? null : CConstructorCall(path, validateArgList(args, "", [], [], classType));
			default: null;
		};
	}
	static function discoverNormalizationBindings(args:Array<FunctionArg>, body:Null<Expr>, classType:ClassType, registered:Array<Null<CoalescingDefaultValue>>):Void {
		if (body == null) return;
		final names = [for (a in args) a.name];
		final oldAllow = allowNormalizationBindingLeaves;
		final oldLocals = normalizationEarlierLocals;
		allowNormalizationBindingLeaves = true;
		normalizationEarlierLocals = [];
		function visit(e:Expr):Void {
			if (e == null) return;
			switch (e.expr) {
				case ExprDef.EVars(vars):
					for (v in vars) {
						if (v.expr == null) continue;
						final parameter = normalizationParameter(v.expr);
						final index = parameter == null ? -1 : names.indexOf(parameter);
						if (index < 0 || !isNullableParameter(args[index]) || registered[index] != null) {
							normalizationEarlierLocals.push(v.name);
							continue;
						}
						if (args[index].value != null) {
							// A registered parameter default does not turn body
							// normalization into an additional sanctioned leaf.
							final oldAllow = allowNormalizationBindingLeaves;
							allowNormalizationBindingLeaves = false;
							matchCoalescingExpression(v.expr, parameter, classType, names.slice(0, index), names);
							allowNormalizationBindingLeaves = oldAllow;
							continue;
						}
						final m = matchCoalescingExpression(v.expr, parameter, classType, names.slice(0, index), names);
						if (m != null && parameter != null) {
							final p = Context.getPosInfos(m.defaultExpr.pos);
							normalizationSourceRanges.push({file: p.file, min: p.min, max: p.max});
							}
						normalizationEarlierLocals.push(v.name);
					}
				default:
			}
			haxe.macro.ExprTools.iter(e, visit);
		}
		visit(body);
		allowNormalizationBindingLeaves = oldAllow;
		normalizationEarlierLocals = oldLocals;
	}

	static function isNullableParameter(arg:FunctionArg):Bool {
		// Optional arguments are represented by `?p:T`; explicit Null<T>
		// annotations are nullable as well.
		if (arg == null) return false;
		if (arg.opt == true) return true;
		return switch (arg.type) {
			case ComplexType.TPath({name: "Null"}): true;
			default: false;
		};
	}

	static function normalizationParameter(e:Expr):Null<String> {
			final cur = unwrapExpr(e);
			if (cur == null) return null;
			return switch (cur.expr) {
				case ExprDef.ETernary(condition, _, _):
					final c = unwrapExpr(condition);
					switch (c == null ? null : c.expr) {
						case ExprDef.EBinop(Binop.OpEq, left, _):
							switch (unwrapExpr(left).expr) { case ExprDef.EConst(AstConstant.CIdent(n)): n; default: null; }
						default: null;
					}
				default: null;
			};
	}
	public static function isNormalizationSource(pos:Position):Bool {
		final infos = Context.getPosInfos(pos);
		for (range in normalizationSourceRanges) if (range.file == infos.file && infos.min == range.min && infos.max == range.max) return true;
		return false;
	}

	static function discoverCoalescingDefaults(args:Array<FunctionArg>, body:Null<Expr>, classType:ClassType, ?outSites:Array<CoalescingSiteInfo>):Array<Null<CoalescingDefaultValue>> {
		final result:Array<Null<CoalescingDefaultValue>> = [for (_ in args) null];
		if (body == null) return result;
		final allParamNames:Array<String> = [for (a in args) a.name];
		final registered:Array<Null<CoalescingSiteInfo>> = [for (_ in args) null];
		for (argIdx in 0...args.length) {
			final arg = args[argIdx];
			if (arg.opt != true || arg.value != null) continue;
			final earlierNames:Array<String> = allParamNames.slice(0, argIdx);
			final candidates:Array<{value:CoalescingDefaultValue, excluded:Expr, defaultExpr:Expr}> = [];
			final oldSuppress = suppressGrammarErrors;
			suppressGrammarErrors = true;
			collectCoalescingCandidates(body, arg.name, classType, earlierNames, allParamNames, candidates);
			suppressGrammarErrors = oldSuppress;
			if (candidates.length > 1) {
				Context.fatalError("coalesced default parameter is consumed more than once", body.pos);
			}
			if (candidates.length == 1) {
				registered[argIdx] = {name: arg.name, argIdx: argIdx, value: candidates[0].value, excluded: candidates[0].excluded, defaultExpr: candidates[0].defaultExpr};
				result[argIdx] = candidates[0].value;
			}
		}
		// Spec 22, Evaluation ordering: a read of a parameter inside the
		// default expression of another registered site is a sanctioned use
		// and does not count toward the consumed-more-than-once rejection.
		final otherDefaults:Array<Expr> = [for (site in registered) if (site != null) site.defaultExpr];
		for (argIdx in 0...args.length) {
			final site = registered[argIdx];
			if (site == null) continue;
			if (countParameterReads(body, site.name, [site.excluded].concat(otherDefaults)) > 0) {
				Context.fatalError("coalesced default parameter is consumed more than once", body.pos);
			}
			recordCoalescingSource(site.defaultExpr.pos);
			if (outSites != null) outSites.push(site);
		}
		return result;
	}

	static function collectCoalescingCandidates(e:Expr, parameterName:String, classType:ClassType, earlierNames:Array<String>, allParamNames:Array<String>, result:Array<{value:CoalescingDefaultValue, excluded:Expr, defaultExpr:Expr}>):Void {
		if (e == null) return;
		switch (e.expr) {
			case ExprDef.EBinop(Binop.OpAssign, lhs, rhs):
				if (isThisField(lhs, parameterName)) {
					final match = matchCoalescingExpression(rhs, parameterName, classType, earlierNames, allParamNames);
					if (match != null) {
						result.push({value: match.value, excluded: e, defaultExpr: match.defaultExpr});
					}
				}
			case ExprDef.EVars(vars):
				for (v in vars) {
					if (v.isFinal == true || v.expr == null) continue;
					final oldSuppress = suppressGrammarErrors;
					suppressGrammarErrors = true;
					final match = matchCoalescingExpression(v.expr, parameterName, classType, earlierNames, allParamNames);
					suppressGrammarErrors = oldSuppress;
					if (match != null) {
						result.push({value: match.value, excluded: v.expr, defaultExpr: match.defaultExpr});
					}
				}
			default:
		}
		haxe.macro.ExprTools.iter(e, child -> collectCoalescingCandidates(child, parameterName, classType, earlierNames, allParamNames, result));
	}

	static function isThisField(e:Expr, fieldName:String):Bool {
		final cur = unwrapExpr(e);
		if (cur == null) return false;
		return switch (cur.expr) {
			case ExprDef.EField(receiver, name):
				name == fieldName && isThisExpression(receiver);
			default: false;
		};
	}

	static function isThisExpression(e:Expr):Bool {
		final cur = unwrapExpr(e);
		return cur != null && switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CIdent("this")): true;
			default: false;
		};
	}

	static function matchCoalescingExpression(e:Expr, parameterName:String, classType:ClassType, earlierNames:Array<String>, allParamNames:Array<String>):Null<{value:CoalescingDefaultValue, defaultExpr:Expr}> {
		final cur = unwrapExpr(e);
		if (cur == null) return null;
		return switch (cur.expr) {
			case ExprDef.ETernary(condition, ifTrue, ifFalse):
				if (isNullCheck(condition, parameterName) && isParameterExpression(ifFalse, parameterName)) {
					final grammarValue = validateCoalescingGrammar(ifTrue, parameterName, earlierNames, allParamNames, classType);
					if (grammarValue != null) {
						{value: grammarValue, defaultExpr: unwrapExpr(ifTrue)};
					} else {
						null;
					}
				} else {
					null;
				}
			default: null;
		};
	}

	/** Classifies an identifier as a parameter, static field, module constant, or type. */
	static function classifyExpr(e:Expr, earlierNames:Array<String>):String {
		final cur = unwrapExpr(e);
		if (cur == null) return "other";
		return switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CIdent(name)):
				if (earlierNames.indexOf(name) >= 0) "parameter" else {
					if (isTypeName(name)) "type" else "other";
				}
			case ExprDef.EField(inner, fieldName):
				final innerClass = classifyExpr(inner, earlierNames);
				if (innerClass == "type") "staticField" else if (innerClass == "parameter") "fieldChain" else "other";
			default: "other";
		};
	}

	static function isInstanceField(classType:ClassType, name:String):Bool {
		final registered = registeredInstanceFields.get(getClassKey(classType));
		if (registered != null && registered.exists(name)) return true;
		for (field in classType.fields.get()) if (field.name == name) return true;
		final local = Context.getLocalClass();
		if (local != null) for (field in local.get().fields.get()) if (field.name == name) return true;
		return false;
	}

	/** Checks whether a name resolves to a type in the compilation (class, enum, typedef, abstract). */
	static function isTypeName(name:String):Bool {
		try {
			final t = Context.getType(name);
			return switch (t) {
				case Type.TType(_, _): true;
				case Type.TEnum(_, _): true;
				case Type.TInst(_, _): true;
				case Type.TAbstract(_, _): true;
				default: false;
			};
		} catch (_:Dynamic) {}
		return false;
	}

	/** Resolves a dotted path to a static field or module constant, returning the full path or null. */
	static function resolveStaticFieldOrConstant(e:Expr, earlierNames:Array<String>):Null<String> {
		final cur = unwrapExpr(e);
		if (cur == null) return null;
		return switch (cur.expr) {
			case ExprDef.EField(inner, fieldName):
				final innerStr = resolveStaticFieldOrConstant(inner, earlierNames);
				if (innerStr != null) innerStr + "." + fieldName else {
					// Check if inner is a type → static field read
					final innerClass = classifyExpr(inner, earlierNames);
					if (innerClass == "type") {
						final fullPath = exprToDotted(inner);
						if (fullPath != null) {
							try {
								switch (Context.getType(fullPath)) {
									case TInst(clsRef, _):
										return getClassKey(clsRef.get()) + "." + fieldName;
									default:
								}
							} catch (_:Dynamic) {}
							fullPath + "." + fieldName;
						} else null;
					} else null;
				}
			case ExprDef.EConst(AstConstant.CIdent(name)):
				// Check if this is a module constant (not a parameter or type)
				final c = classifyExpr(cur, earlierNames);
				if (c == "other") {
					// Verify it resolves to a module static field
					try {
						final mod = Context.getLocalModule();
						final moduleTypes = Context.getModule(mod);
						for (mt in moduleTypes) {
							switch (mt) {
								case TInst(clsRef, _):
									final cls = clsRef.get();
									for (f in cls.statics.get()) {
										if (f.name == name) return getClassKey(cls) + "." + name;
									}
								default:
							}
						}
					} catch (_:Dynamic) {}
					null;
				} else null;
			default: null;
		};
	}

	/**
		Validates the default expression E of `p == null ? E : p` against
		the recursive grammar. Returns the CoalescingDefaultValue tree or
		null when the expression is not sanctioned.
	*/
	static function validateCoalescingGrammar(e:Expr, parameterName:String, earlierNames:Array<String>, allParamNames:Array<String>, classType:ClassType):Null<CoalescingDefaultValue> {
		final cur = unwrapExpr(e);
		if (cur == null) return null;

		// 1. Closed value leaves (literals, null, empty containers, infinity, enum constructors)
		final closedResult = coalescingValueTry(cur, classType);
		if (closedResult != null) return closedResult;

		// 2. Parameter reference root (earlier parameters only)
		if (cur.expr != null) {
			switch (cur.expr) {
					case ExprDef.EConst(AstConstant.CIdent(name)):
					if (earlierNames.indexOf(name) >= 0) {
						return CParameterRead(name);
					}
					if (allowNormalizationBindingLeaves && normalizationEarlierLocals.indexOf(name) >= 0) return CLocalRead(name);
					if (isInstanceField(classType, name) && allowNormalizationBindingLeaves) return CInstanceFieldRead(name);
					// Check for later parameter references or the defaulted parameter itself
					if (allParamNames.indexOf(name) >= 0) {
						if (name == parameterName) {
							Context.fatalError("coalesced default parameter is consumed more than once", cur.pos);
						}
						laterParameterError(cur.pos);
						return null;
					}
				default:
			}
		}

		// 3. Normalization-only roots: instance fields and earlier locals.
		if (allowNormalizationBindingLeaves) switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CIdent(name)) if (isInstanceField(classType, name)): return CInstanceFieldRead(name);
			case ExprDef.EField(inner, name) if (allowNormalizationBindingLeaves && isThisExpression(inner) && isInstanceField(classType, name)): return CInstanceFieldRead(name);
			default:
		}

		// 4. Static-field / top-level constant root (skip parameter names)
		final staticPath = resolveStaticFieldOrConstant(cur, earlierNames);
		if (staticPath != null) {
			return CFieldAccess(CParameterRead(staticPath), "");
		}

		// 4. Field access chain over parameter references
		if (cur.expr != null) {
			switch (cur.expr) {
				case ExprDef.EField(inner, fieldName):
					if (allowNormalizationBindingLeaves && isThisExpression(inner) && isInstanceField(classType, fieldName)) return CInstanceFieldRead(fieldName);
					final innerClass = classifyExpr(inner, earlierNames);
					if (innerClass == "type") {
						// Static field read; handled above; fall through
					} else if (innerClass == "parameter" || innerClass == "fieldChain") {
						final innerValue = validateCoalescingGrammar(inner, parameterName, earlierNames, allParamNames, classType);
						if (innerValue != null) {
							return CFieldAccess(innerValue, fieldName);
						}
					}
				default:
			}
		}

		// 5. Constructor invocation: its arguments recurse through the grammar.
		if (cur.expr != null) {
			switch (cur.expr) {
				case ExprDef.ENew(typePath, callArgs):
					final argValues = validateArgList(callArgs, parameterName, earlierNames, allParamNames, classType);
					if (argValues != null) return CConstructorCall(typePath.pack.length == 0 ? typePath.name : typePath.pack.join(".") + "." + typePath.name, argValues);
				default:
			}
		}

		// 6. Instance method call: receiver and args are grammar expressions
		//    Static call: receiver is a type, args are grammar expressions
		if (cur.expr != null) {
			switch (cur.expr) {
				case ExprDef.ECall(callee, callArgs):
					final calleeExpr = unwrapExpr(callee);
					if (calleeExpr != null) {
						switch (calleeExpr.expr) {
							case ExprDef.EField(innerClassField, methodName):
								final innerClassExpr = unwrapExpr(innerClassField);
								if (innerClassExpr != null) {
								switch (innerClassExpr.expr) {
									case ExprDef.EField(innerReceiver, typeName):
										// Static call: Outer.Inner.method(args)
										final fullTypePath = exprToDotted(innerClassField);
										if (fullTypePath != null && isTypeName(fullTypePath)) {
											final argValues = validateArgList(callArgs, parameterName, earlierNames, allParamNames, classType);
											if (argValues != null) return CStaticCall(fullTypePath + "." + methodName, argValues);
										}
									case ExprDef.EConst(AstConstant.CIdent(typeName)):
										// Static call: ClassName.method(args)
										if (isTypeName(typeName) && isCompiledStaticType(typeName)) {
											final argValues = validateArgList(callArgs, parameterName, earlierNames, allParamNames, classType);
											if (argValues != null) return CStaticCall(typeName + "." + methodName, argValues);
										}
									default:
								}
								}
								// Instance method call: receiver.method(args)
								final receiverClass = classifyExpr(innerClassField, earlierNames);
								if (receiverClass != "type") {
									final receiverValue = validateCoalescingGrammar(innerClassField, parameterName, earlierNames, allParamNames, classType);
									if (receiverValue != null) {
										final argValues = validateArgList(callArgs, parameterName, earlierNames, allParamNames, classType);
										if (argValues != null) return CMethodCall(receiverValue, methodName, argValues);
									}
								}
							case ExprDef.EConst(AstConstant.CIdent(funcName)):
								// Possible static call: funcName(args)
								if (earlierNames.indexOf(funcName) < 0) {
									final argValues = validateArgList(callArgs, parameterName, earlierNames, allParamNames, classType);
									if (argValues != null) return CStaticCall(classType.name + "." + funcName, argValues);
								}
							default:
						}
					}
				default:
			}
		}

		// 7. Conditional: cond ? t : f
		if (cur.expr != null) {
			switch (cur.expr) {
				case ExprDef.ETernary(condition, ifTrue, ifFalse):
					final cVal = validateCoalescingGrammar(condition, parameterName, earlierNames, allParamNames, classType);
					final tVal = validateCoalescingGrammar(ifTrue, parameterName, earlierNames, allParamNames, classType);
					final fVal = validateCoalescingGrammar(ifFalse, parameterName, earlierNames, allParamNames, classType);
					if (cVal != null && tVal != null && fVal != null) {
						return CConditional(cVal, tVal, fVal);
					}
				default:
			}
		}

		// 8. Binary operator: left op right
		if (cur.expr != null) {
			switch (cur.expr) {
				case ExprDef.EBinop(op, left, right):
					final lVal = validateCoalescingGrammar(left, parameterName, earlierNames, allParamNames, classType);
					final rVal = validateCoalescingGrammar(right, parameterName, earlierNames, allParamNames, classType);
					if (lVal != null && rVal != null) {
						return CBinaryOp(op, lVal, rVal);
					}
				default:
			}
		}

		// Unrecognized node
		coalescingError(cur.pos);
		return null;
	}

	static function isCompiledStaticType(path:String):Bool {
		try {
			switch (Context.getType(path)) {
				case Type.TInst(ref, _): return true;
				default:
			}
		} catch (_:Dynamic) {}
		return false;
	}


	static function validateArgList(args:Array<Expr>, parameterName:String, earlierNames:Array<String>, allParamNames:Array<String>, classType:ClassType):Null<Array<CoalescingDefaultValue>> {
		final values:Array<CoalescingDefaultValue> = [];
		for (a in args) {
			final v = validateCoalescingGrammar(a, parameterName, earlierNames, allParamNames, classType);
			if (v == null) return null;
			values.push(v);
		}
		return values;
	}

	/** Tries to recognize a closed value; returns null for non-closed expressions. */
	static function coalescingValueTry(e:Expr, classType:ClassType):Null<CoalescingDefaultValue> {
		final cur = unwrapExpr(e);
		if (cur == null) return null;
		return switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CInt(s)): CInt(Std.parseInt(s));
			case ExprDef.EConst(AstConstant.CFloat(s)): CFloat(s);
			case ExprDef.EConst(AstConstant.CString(s, _)): CString(s);
			case ExprDef.EConst(AstConstant.CIdent("true")): CBool(true);
			case ExprDef.EConst(AstConstant.CIdent("false")): CBool(false);
			case ExprDef.EConst(AstConstant.CIdent("null")): CNull;
			case ExprDef.EUnop(Unop.OpNeg, _, inner):
				final value = unwrapExpr(inner);
				if (value != null) {
					switch (value.expr) {
						case ExprDef.EConst(AstConstant.CInt(s)): CInt(-Std.parseInt(s));
						case ExprDef.EConst(AstConstant.CFloat(s)): CFloat("-" + s);
						default: null;
					}
				} else null;
			case ExprDef.EArrayDecl(values): values.length == 0 ? CEmptyArray : null;
			case ExprDef.ENew(typePath, params):
				(typePath.pack.length == 0 && (typePath.name == "Map" || typePath.name == "StringMap") && params.length == 0) ? CEmptyMap : null;
			case ExprDef.EField(receiver, fieldName):
				if (exprToDotted(receiver) == "Math") {
					if (fieldName == "POSITIVE_INFINITY") return CPositiveInfinity;
					if (fieldName == "NEGATIVE_INFINITY") return CNegativeInfinity;
				}
				final enumRef = resolveEnum(receiver);
				if (enumRef != null) {
					final en = enumRef.get();
					if (en.constructs.exists(fieldName)) {
						final enumField = en.constructs.get(fieldName);
						switch (enumField.type) {
							case Type.TEnum(_, _): CEnum(enumRef, enumField);
							default: null;
						}
					} else null;
				} else null;
			case ExprDef.EConst(AstConstant.CIdent(ident)):
				final enumValue = resolveUnqualifiedEnumConstructor(ident, classType);
				if (enumValue != null) {
					switch (enumValue) {
						case VEnum(enumRef, enumField): CEnum(enumRef, enumField);
						default: null;
					}
				} else null;
			default: null;
		};
	}


	static function isNullCheck(e:Expr, parameterName:String):Bool {
		final cur = unwrapExpr(e);
		if (cur == null) return false;
		return switch (cur.expr) {
			case ExprDef.EBinop(Binop.OpEq, left, right):
				isParameterExpression(left, parameterName) && isNullExpression(right);
			default: false;
		};
	}

	static function isParameterExpression(e:Expr, parameterName:String):Bool {
		final cur = unwrapExpr(e);
		return cur != null && switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CIdent(name)): name == parameterName;
			default: false;
		};
	}

	static function isNullExpression(e:Expr):Bool {
		final cur = unwrapExpr(e);
		return cur != null && switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CIdent("null")): true;
			default: false;
		};
	}

	static function coalescingValue(e:Expr, classType:ClassType):CoalescingDefaultValue {
		final cur = unwrapExpr(e);
		if (cur == null) coalescingError(e.pos);
		switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CInt(s)):
				return CInt(Std.parseInt(s));
			case ExprDef.EConst(AstConstant.CFloat(s)):
				return CFloat(s);
			case ExprDef.EConst(AstConstant.CString(s, _)):
				return CString(s);
			case ExprDef.EConst(AstConstant.CIdent("true")):
				return CBool(true);
			case ExprDef.EConst(AstConstant.CIdent("false")):
				return CBool(false);
			case ExprDef.EConst(AstConstant.CIdent("null")):
				return CNull;
			case ExprDef.EUnop(Unop.OpNeg, _, inner):
				final value = unwrapExpr(inner);
				if (value != null) {
					switch (value.expr) {
						case ExprDef.EConst(AstConstant.CInt(s)): return CInt(-Std.parseInt(s));
						case ExprDef.EConst(AstConstant.CFloat(s)): return CFloat("-" + s);
						default:
					}
				}
				coalescingError(cur.pos);
			case ExprDef.EArrayDecl(values):
				if (values.length == 0) return CEmptyArray;
				coalescingError(cur.pos);
			case ExprDef.ENew(typePath, params):
				if (typePath.pack.length == 0 && typePath.name == "Map" && params.length == 0) return CEmptyMap;
				coalescingError(cur.pos);
			case ExprDef.EField(receiver, fieldName):
				if (exprToDotted(receiver) == "Math") {
					if (fieldName == "POSITIVE_INFINITY") return CPositiveInfinity;
					if (fieldName == "NEGATIVE_INFINITY") return CNegativeInfinity;
				}
				final enumRef = resolveEnum(receiver);
				if (enumRef != null) {
					final en = enumRef.get();
					if (en.constructs.exists(fieldName)) {
						final enumField = en.constructs.get(fieldName);
						switch (enumField.type) {
							case Type.TEnum(_, _): return CEnum(enumRef, enumField);
							default:
						}
					}
				}
				coalescingError(cur.pos);
			case ExprDef.EConst(AstConstant.CIdent(ident)):
				final enumValue = resolveUnqualifiedEnumConstructor(ident, classType);
				if (enumValue != null) {
					switch (enumValue) {
						case VEnum(enumRef, enumField): return CEnum(enumRef, enumField);
						default:
					}
				}
				coalescingError(cur.pos);
			default:
				coalescingError(cur.pos);
		}
		return CNull;
	}

	static function coalescingError(pos:Position):Void {
		if (!suppressGrammarErrors) Context.fatalError("coalesced default expression is not sanctioned", pos);
	}

	static function laterParameterError(pos:Position):Void {
		Context.fatalError("coalesced default expression may reference earlier parameters only", pos);
	}

	/** True when the coalescing value tree reads any parameter reference. */
	public static function readsParameter(value:CoalescingDefaultValue):Bool {
		return switch (value) {
			case CParameterRead(_): true;
			case CFieldAccess(CParameterRead(_), ""): false;
			case CFieldAccess(receiver, _): readsParameter(receiver);
			case CMethodCall(receiver, _, args):
				readsParameter(receiver) || argsHaveParameter(args);
			case CStaticCall(_, args): argsHaveParameter(args);
			case CConditional(c, t, f): readsParameter(c) || readsParameter(t) || readsParameter(f);
			case CBinaryOp(_, l, r): readsParameter(l) || readsParameter(r);
			case CConstructorCall(_, args): argsHaveParameter(args);
			default: false;
		};
	}

	static function argsHaveParameter(args:Array<CoalescingDefaultValue>):Bool {
		for (a in args) {
			if (readsParameter(a)) return true;
		}
		return false;
	}

	static function recordCoalescingSource(pos:Position):Void {
		final infos = Context.getPosInfos(pos);
		coalescingSourceRanges.push({file: infos.file, min: infos.min, max: infos.max});
	}

	/** True only for a source expression accepted during registration. */
	public static function isRegisteredCoalescingSource(pos:Position):Bool {
		final infos = Context.getPosInfos(pos);
		for (range in coalescingSourceRanges) {
			if (range.file == infos.file && infos.min >= range.min && infos.max <= range.max) {
				return true;
			}
		}
		return false;
	}

	static function countParameterReads(e:Expr, parameterName:String, excluded:Array<Expr>):Int {
		if (e == null) return 0;
		for (skip in excluded) {
			if (e == skip) return 0;
		}
		var count = 0;
		switch (e.expr) {
			case ExprDef.EConst(AstConstant.CIdent(name)):
				if (name == parameterName) count++;
			default:
		}
		haxe.macro.ExprTools.iter(e, child -> count += countParameterReads(child, parameterName, excluded));
		return count;
	}

	/**
	 * Spec 22, Evaluation ordering: a later site reads the normalized value
	 * of an earlier coalesced parameter, while plain Haxe execution reads
	 * the raw nullable binding. This pass rewrites each read of an earlier
	 * coalesced parameter inside a later site's default expression into the
	 * inline normalization `p == null ? E : p`, with `E` a deep copy of the
	 * earlier site's default expression. Targets render defaults from the
	 * registered values, so the rewrite changes no target output.
	 */
	public static function rewriteCrossSiteReads(body:Null<Expr>, sites:Array<CoalescingSiteInfo>):Void {
		if (body == null || sites.length == 0) return;
		final coalescedByName:Map<String, CoalescingSiteInfo> = new Map();
		for (site in sites) {
			coalescedByName.set(site.name, site);
		}
		for (site in sites) {
			final readNames:Array<String> = [];
			collectParameterReadNames(site.value, readNames);
			final replacements:Map<String, Expr> = new Map();
			for (name in readNames) {
				final earlier = coalescedByName.get(name);
				if (earlier == null || earlier.argIdx >= site.argIdx) continue;
				replacements.set(name, makeNormalizationTernary(name, cloneExpr(earlier.defaultExpr), earlier.defaultExpr.pos));
			}
			if (Lambda.count(replacements) == 0) continue;
			site.defaultExpr.expr = replaceParameterReads(site.defaultExpr, replacements).expr;
		}
	}

	/** Names of every parameter referenced anywhere in a coalescing value tree. */
	static function collectParameterReadNames(value:CoalescingDefaultValue, out:Array<String>):Void {
		switch (value) {
			case CParameterRead(name):
				out.push(name);
			case CFieldAccess(receiver, _):
				collectParameterReadNames(receiver, out);
			case CMethodCall(receiver, _, args):
				collectParameterReadNames(receiver, out);
				for (arg in args) collectParameterReadNames(arg, out);
			case CStaticCall(_, args):
				for (arg in args) collectParameterReadNames(arg, out);
			case CConditional(condition, ifTrue, ifFalse):
				collectParameterReadNames(condition, out);
				collectParameterReadNames(ifTrue, out);
				collectParameterReadNames(ifFalse, out);
			case CBinaryOp(_, left, right):
				collectParameterReadNames(left, out);
				collectParameterReadNames(right, out);
			case CConstructorCall(_, args):
				for (arg in args) collectParameterReadNames(arg, out);
			default:
		}
	}

	/** Replaces bare reads of the named parameters with the given expressions. */
	static function replaceParameterReads(e:Expr, replacements:Map<String, Expr>):Expr {
		switch (e.expr) {
			case ExprDef.EConst(AstConstant.CIdent(name)):
				final replacement = replacements.get(name);
				if (replacement != null) return replacement;
			default:
		}
		return haxe.macro.ExprTools.map(e, child -> replaceParameterReads(child, replacements));
	}

	static function makeNormalizationTernary(parameterName:String, defaultExprCopy:Expr, pos:Position):Expr {
		final paramRead = {pos: pos, expr: ExprDef.EConst(AstConstant.CIdent(parameterName))};
		final nullLiteral = {pos: pos, expr: ExprDef.EConst(AstConstant.CIdent("null"))};
		final condition = {pos: pos, expr: ExprDef.EBinop(Binop.OpEq, paramRead, nullLiteral)};
		final fallbackRead = {pos: pos, expr: ExprDef.EConst(AstConstant.CIdent(parameterName))};
		return {pos: pos, expr: ExprDef.ETernary(condition, defaultExprCopy, fallbackRead)};
	}

	/** Deep copy of an expression tree; the mapper returning null rebuilds every node. */
	static function cloneExpr(e:Expr):Expr {
		return haxe.macro.ExprTools.map(e, _ -> null);
	}

	static function evalConstantExpr(e:Expr, classType:ClassType):DefaultArgValue {
		var cur = unwrapExpr(e);
		if (cur == null) {
			v16Error(e.pos);
		}
		switch (cur.expr) {
			case ExprDef.EConst(AstConstant.CInt(s)):
				return VInt(Std.parseInt(s));
			case ExprDef.EConst(AstConstant.CFloat(s)):
				return VFloat(s);
			case ExprDef.EConst(AstConstant.CString(s, _)):
				return VString(s);
			case ExprDef.EConst(AstConstant.CIdent("true")):
				return VBool(true);
			case ExprDef.EConst(AstConstant.CIdent("false")):
				return VBool(false);
			case ExprDef.EConst(AstConstant.CIdent("null")):
				return VNull;
			case ExprDef.EUnop(Unop.OpNeg, _, inner):
				final unwrapped = unwrapExpr(inner);
				if (unwrapped != null) {
					switch (unwrapped.expr) {
						case ExprDef.EConst(AstConstant.CInt(s)):
							return VInt(-Std.parseInt(s));
						case ExprDef.EConst(AstConstant.CFloat(s)):
							return VFloat("-" + s);
						default:
							v16Error(cur.pos);
					}
				} else {
					v16Error(cur.pos);
				}
			case ExprDef.EField(receiver, constructName):
				final enumRef = resolveEnum(receiver);
				if (enumRef != null) {
					final en = enumRef.get();
					if (en.constructs.exists(constructName)) {
						final ef = en.constructs.get(constructName);
						switch (ef.type) {
							case Type.TEnum(_, _):
								return VEnum(enumRef, ef);
							default:
								v16Error(cur.pos);
						}
					}
				}
				v16Error(cur.pos);
			case ExprDef.EConst(AstConstant.CIdent(ident)):
				final enumVal = resolveUnqualifiedEnumConstructor(ident, classType);
				if (enumVal != null) {
					return enumVal;
				}
				v16Error(cur.pos);
			default:
				v16Error(cur.pos);
		}
		return VNull;
	}

	static function unwrapExpr(e:Expr):Null<Expr> {
		var cur = e;
		while (cur != null) {
			switch (cur.expr) {
				case ExprDef.EParenthesis(inner) | ExprDef.EMeta(_, inner):
					cur = inner;
				default:
					return cur;
			}
		}
		return cur;
	}

	static function v16Error(pos:Position):Void {
		Context.fatalError("default argument values accept compile-time constants only", pos);
	}

	static function resolveEnum(receiver:Expr):Null<Ref<EnumType>> {
		final fullPath = exprToDotted(receiver);
		if (fullPath == null) return null;
		try {
			final t = Context.getType(fullPath);
			switch (t) {
				case Type.TEnum(enRef, _): return enRef;
				default:
			}
		} catch (e:Dynamic) {}

		try {
			final mod = Context.getLocalModule();
			final t = Context.getType(mod + "." + fullPath);
			switch (t) {
				case Type.TEnum(enRef, _): return enRef;
				default:
			}
		} catch (e:Dynamic) {}

		final localClass = Context.getLocalClass();
		if (localClass != null) {
			final cls = localClass.get();
			if (cls.pack.length > 0) {
				try {
					final t = Context.getType(cls.pack.join(".") + "." + fullPath);
					switch (t) {
						case Type.TEnum(enRef, _): return enRef;
						default:
					}
				} catch (e:Dynamic) {}
			}
		}

		try {
			final imports = Context.getLocalImports();
			for (imp in imports) {
				final impPath = [for (p in imp.path) p.name].join(".");
				try {
					final t = Context.getType(impPath + "." + fullPath);
					switch (t) {
						case Type.TEnum(enRef, _): return enRef;
						default:
					}
				} catch (e:Dynamic) {}
			}
		} catch (e:Dynamic) {}

		return null;
	}

	static function exprToDotted(e:Expr):Null<String> {
		return switch (e.expr) {
			case ExprDef.EConst(AstConstant.CIdent(name)): name;
			case ExprDef.EField(inner, name):
				final left = exprToDotted(inner);
				left == null ? null : left + "." + name;
			case ExprDef.EParenthesis(inner): exprToDotted(inner);
			default: null;
		};
	}

	static function resolveUnqualifiedEnumConstructor(ident:String, classType:ClassType):Null<DefaultArgValue> {
		try {
			final moduleTypes = Context.getModule(Context.getLocalModule());
			for (mt in moduleTypes) {
				switch (mt) {
					case TEnum(enRef, _):
						final en = enRef.get();
						if (en.constructs.exists(ident)) {
							final ef = en.constructs.get(ident);
							switch (ef.type) {
								case TEnum(_, _): return VEnum(enRef, ef);
								default:
							}
						}
					default:
				}
			}
		} catch (e:Dynamic) {}

		try {
			final imports = Context.getLocalImports();
			for (imp in imports) {
				final impPath = [for (p in imp.path) p.name].join(".");
				try {
					final t = Context.getType(impPath);
					switch (t) {
						case Type.TEnum(enRef, _):
							final en = enRef.get();
							if (en.constructs.exists(ident)) {
								final ef = en.constructs.get(ident);
								switch (ef.type) {
									case Type.TEnum(_, _): return VEnum(enRef, ef);
									default:
								}
							}
						default:
					}
				} catch (e:Dynamic) {}
			}
		} catch (e:Dynamic) {}

		return null;
	}

	public static function completeRootExpr(classType:ClassType, fieldName:String, root:TypedExpr):Void {
		if (root == null) return;
		completeExpr(getClassKey(classType), fieldName, root, false);
	}

	/** Rust has no parameter-default syntax, so coalescing omissions become None. */
	public static function completeRootExprForRust(classType:ClassType, fieldName:String, root:TypedExpr):Void {
		if (root == null) return;
		completeExpr(getClassKey(classType), fieldName, root, true);
	}

	/**
		Rust static-field initializers need the same None completion as
		function bodies. The per-function pass visits method and function
		bodies only, so a construction inside a static initializer keeps
		its omitted coalescing arguments unless this entry runs over the
		initializer expression.
	*/
	public static function completeStaticInitializerForRust(classType:ClassType, fieldName:String, init:Null<TypedExpr>):Void {
		if (init == null) return;
		completeExpr(getClassKey(classType), fieldName, init, true);
	}

	static function completeExpr(classKey:String, fieldName:String, e:TypedExpr, rustTarget:Bool):Void {
		if (e == null) return;
		switch (e.expr) {
			case TypedExprDef.TFunction(f):
				completeExpr(classKey, fieldName, f.expr, rustTarget);
			default:
				haxe.macro.TypedExprTools.iter(e, child -> completeExpr(classKey, fieldName, child, rustTarget));
		}
		switch (e.expr) {
			case TypedExprDef.TCall(callee, args):
				completeCall(classKey, fieldName, e, callee, args, rustTarget);
			case TypedExprDef.TNew(c, _, args):
				completeNew(e, c.get(), args, rustTarget);
			default:
		}
	}

	static function completeCall(classKey:String, fieldName:String, callExpr:TypedExpr, callee:TypedExpr, args:Array<TypedExpr>, rustTarget:Bool):Void {
		if (callee == null) return;
		final followed = Context.follow(callee.t);
		final params:Array<{name:String, opt:Bool, t:Type}> = switch (followed) {
			case Type.TFun(argsList, _): argsList;
			default: return;
		};
		if (args.length >= params.length) {
			return;
		}

		final defaults = findDefaultsForCallee(classKey, fieldName, callee);

		for (i in args.length...params.length) {
			final param = params[i];
			final defVal:Null<DefaultArgValue> = (defaults != null && i < defaults.length) ? defaults[i] : null;

			if (defVal != null) {
				switch (defVal) {
					case VCoalescing(_):
						if (rustTarget) args.push(makeTypedConst(VNull, param.t, callExpr.pos));
					default:
						args.push(makeTypedConst(defVal, param.t, callExpr.pos));
				}
			} else if (param.opt) {
				args.push(makeTypedConst(VNull, param.t, callExpr.pos));
			}
		}
	}

	static function stripWrap(e:TypedExpr):TypedExpr {
		if (e == null) return null;
		return switch (e.expr) {
			case TypedExprDef.TParenthesis(inner) | TypedExprDef.TMeta(_, inner) | TypedExprDef.TCast(inner, _):
				stripWrap(inner);
			default: e;
		};
	}

	static function findDefaultsForCallee(classKey:String, fieldName:String, callee:TypedExpr):Null<Array<Null<DefaultArgValue>>> {
		final unwrapped = stripWrap(callee);
		switch (unwrapped.expr) {
			case TypedExprDef.TField(receiver, fa):
				return findDefaultsForFieldAccess(receiver, fa);
			case TypedExprDef.TLocal(v):
				final precise = localDefaults.get(classKey + ":" + fieldName + ":" + v.name);
				if (precise != null) {
					return precise;
				}
				return uniqueByName(localNameCounts, localDefaultsByName, v.name, "local function", callee.pos);
			default:
				return null;
		}
	}

	/**
	 * A by-name fallback may serve only a name that carries exactly one
	 * registration in the whole compilation; several registrations with no
	 * precise hit are ambiguous. The build stops without a unique registration.
	 */
	static function uniqueByName(counts:Map<String, Int>, byName:Map<String, Array<Null<DefaultArgValue>>>, name:String, kind:String, pos:Position):Null<Array<Null<DefaultArgValue>>> {
		if (!byName.exists(name)) {
			return null;
		}
		if (counts.get(name) > 1) {
			Context.fatalError("default argument lookup is ambiguous for " + kind + " " + name, pos);
		}
		return byName.get(name);
	}

	static function findDefaultsForFieldAccess(receiver:TypedExpr, fa:FieldAccess):Null<Array<Null<DefaultArgValue>>> {
		switch (fa) {
			case FieldAccess.FInstance(c, _, cf) | FieldAccess.FStatic(c, cf):
				return lookupFieldDefaults(c.get(), cf.get().name);
			case FieldAccess.FAnon(cf):
				final fieldName = cf.get().name;
				if (receiver != null) {
					switch (Context.follow(receiver.t)) {
						case Type.TInst(c, _):
							return lookupFieldDefaults(c.get(), fieldName);
						default:
					}
				}
				if (fieldDefaultsByName.exists(fieldName)) {
					return fieldDefaultsByName.get(fieldName);
				}
				return null;
			case FieldAccess.FClosure(c, cf):
				final fieldName = cf.get().name;
				if (c != null) {
					return lookupFieldDefaults(c.c.get(), fieldName);
				}
				if (fieldDefaultsByName.exists(fieldName)) {
					return fieldDefaultsByName.get(fieldName);
				}
				return null;
			default:
				return null;
		}
	}

	static function lookupFieldDefaults(cls:ClassType, fieldName:String):Null<Array<Null<DefaultArgValue>>> {
		if (cls == null) return null;
		final classKey = getClassKey(cls);
		final key = classKey + ":" + fieldName;
		if (fieldDefaults.exists(key)) {
			return fieldDefaults.get(key);
		}
		for (iface in cls.interfaces) {
			final ifaceCls = iface.t.get();
			final ifaceRes = lookupFieldDefaults(ifaceCls, fieldName);
			if (ifaceRes != null) return ifaceRes;
		}
		if (cls.superClass != null) {
			final superCls = cls.superClass.t.get();
			final superRes = lookupFieldDefaults(superCls, fieldName);
			if (superRes != null) return superRes;
		}
		return uniqueByName(fieldNameCounts, fieldDefaultsByName, fieldName, "method", cls.pos);
	}

	static function lookupFieldDefaultsExact(cls:ClassType, fieldName:String):Null<Array<Null<DefaultArgValue>>> {
		if (cls == null) return null;
		final classKey = getClassKey(cls);
		final key = classKey + ":" + fieldName;
		if (fieldDefaults.exists(key)) {
			return fieldDefaults.get(key);
		}
		for (iface in cls.interfaces) {
			final ifaceRes = lookupFieldDefaultsExact(iface.t.get(), fieldName);
			if (ifaceRes != null) return ifaceRes;
		}
		if (cls.superClass != null) {
			final superRes = lookupFieldDefaultsExact(cls.superClass.t.get(), fieldName);
			if (superRes != null) return superRes;
		}
		return null;
	}

	/** Returns the sanctioned default for one declared parameter, if any. */
	public static function coalescingDefaultAt(classType:ClassType, fieldName:String, index:Int):Null<CoalescingDefaultValue> {
		final defaults = lookupFieldDefaultsExact(classType, fieldName);
		if (defaults == null || index < 0 || index >= defaults.length) return null;
		return switch (defaults[index]) {
			case VCoalescing(value): value;
			default: null;
		};
	}

	/** True when the coalescing default for a specific parameter reads an earlier parameter. */
	public static function coalescingReadsParamForParam(classType:ClassType, fieldName:String, parameterName:String):Bool {
		final key = getClassKey(classType) + ":" + fieldName + ":" + parameterName;
		return fieldCoalescingReadsParam.exists(key) && fieldCoalescingReadsParam.get(key);
	}

	/** True when the local coalescing default reads an earlier parameter. */
	public static function coalescingReadsParamForLocalParam(classType:ClassType, fieldName:String, localName:String, parameterName:String):Bool {
		if (classType == null) return false;
		final key = getClassKey(classType) + ":" + fieldName + ":" + localName + ":" + parameterName;
		return localCoalescingReadsParam.exists(key) && localCoalescingReadsParam.get(key);
	}

	/** Returns a sanctioned default by the exact class/field/parameter identity. */
	public static function coalescingDefaultForParam(classType:ClassType, fieldName:String, parameterName:String):Null<CoalescingDefaultValue> {
		return lookupFieldCoalescing(classType, fieldName, parameterName);
	}

	public static function coalescingDefaultForLocalParam(classType:ClassType, fieldName:String, localName:String, parameterName:String):Null<CoalescingDefaultValue> {
		if (classType == null) return null;
		return localCoalescing.get(getClassKey(classType) + ":" + fieldName + ":" + localName + ":" + parameterName);
	}

	static function lookupFieldCoalescing(cls:ClassType, fieldName:String, parameterName:String):Null<CoalescingDefaultValue> {
		if (cls == null) return null;
		final key = getClassKey(cls) + ":" + fieldName + ":" + parameterName;
		if (fieldCoalescing.exists(key)) return fieldCoalescing.get(key);
		for (iface in cls.interfaces) {
			final value = lookupFieldCoalescing(iface.t.get(), fieldName, parameterName);
			if (value != null) return value;
		}
		if (cls.superClass != null) {
			final value = lookupFieldCoalescing(cls.superClass.t.get(), fieldName, parameterName);
			if (value != null) return value;
		}
		return null;
	}

	/**
		Recognizes the typed shape of the one sanctioned coalescing site. The
		caller still checks the class/field registry so an arbitrary ternary is
		never treated as a default.
	*/
	public static function coalescingSite(e:TypedExpr):Null<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> {
		final cur = unwrapTypedExpr(e);
		if (cur == null) return null;
		return switch (cur.expr) {
			case TypedExprDef.TIf(condition, ifTrue, ifFalse):
				final parameter = typedNullCheckParameter(condition);
				if (parameter != null && isTypedParameter(ifFalse, parameter)) {
					{parameter: parameter, defaultExpr: unwrapTypedExpr(ifTrue), valueExpr: unwrapTypedExpr(ifFalse)};
				} else {
					null;
				}
			default: null;
		};
	}

	public static function hasNestedConditional(e:TypedExpr):Bool {
		var found = false;
		function visit(x:TypedExpr):Void {
			if (x == null || found) return;
			switch (x.expr) {
				case TypedExprDef.TIf(_, _, _): found = true;
				default: haxe.macro.TypedExprTools.iter(x, visit);
			}
		}
		haxe.macro.TypedExprTools.iter(e, visit);
		return found;
	}
	public static function isCoalescingShape(e:TypedExpr):Bool {
		final cur = unwrapTypedExpr(e);
		if (cur == null) return false;
		return switch (cur.expr) {
			case TypedExprDef.TIf(condition, _, ifFalse):
				final parameter = typedNullCheckParameter(condition);
				parameter != null && isTypedParameter(ifFalse, parameter);
			default: false;
		};
	}
	public static function coalescingSites(root:TypedExpr):Array<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> {
		final result:Array<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> = [];
		if (root == null) return result;
		collectTypedCoalescingSites(root, result, true);
		return result;
	}

	/** Collects sites in one function body, leaving nested function bodies to their own pass. */
	public static function coalescingSitesForFunction(root:TypedExpr):Array<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> {
		final result:Array<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> = [];
		if (root == null) return result;
		collectTypedCoalescingSites(root, result, false);
		return result;
	}

	static function collectTypedCoalescingSites(e:TypedExpr, result:Array<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}>, includeNestedFunctions:Bool):Void {
		if (e == null) return;
		final site = coalescingSite(e);
		if (site != null) result.push(site);
		if (!includeNestedFunctions) {
			switch (e.expr) {
				case TypedExprDef.TFunction(_): return;
				default:
			}
		}
		haxe.macro.TypedExprTools.iter(e, child -> collectTypedCoalescingSites(child, result, includeNestedFunctions));
	}

	static function unwrapTypedExpr(e:TypedExpr):Null<TypedExpr> {
		var cur = e;
		while (cur != null) {
			switch (cur.expr) {
				case TypedExprDef.TParenthesis(inner) | TypedExprDef.TMeta(_, inner) | TypedExprDef.TCast(inner, _):
					cur = inner;
				case TypedExprDef.TBlock(expressions) if (expressions.length == 1):
					cur = expressions[0];
				default:
					return cur;
			}
		}
		return cur;
	}

	static function typedNullCheckParameter(e:TypedExpr):Null<String> {
		final cur = unwrapTypedExpr(e);
		if (cur == null) return null;
		return switch (cur.expr) {
			case TypedExprDef.TBinop(Binop.OpEq, left, right):
				final leftValue = unwrapTypedExpr(left);
				final rightValue = unwrapTypedExpr(right);
				if (leftValue != null && rightValue != null) {
					switch (leftValue.expr) {
						case TypedExprDef.TLocal(v):
							switch (rightValue.expr) {
								case TypedExprDef.TConst(TConstant.TNull): return v.name;
								default:
							}
						default:
					}
				}
				null;
			default: null;
		};
	}

	static function isTypedParameter(e:TypedExpr, parameterName:String):Bool {
		final cur = unwrapTypedExpr(e);
		return cur != null && switch (cur.expr) {
			case TypedExprDef.TLocal(v): v.name == parameterName;
			default: false;
		};
	}

	/** Removes the Null<T> wrapper for native-default target parameters. */
	public static function withoutNull(t:Type):Type {
		if (t == null) return t;
		return switch (t) {
			case Type.TAbstract(abstractRef, params) if (abstractRef.get().name == "Null" && params.length == 1): params[0];
			case Type.TLazy(fun): withoutNull(fun());
			default: t;
		};
	}

	/** Keeps a nullable target parameter when its sanctioned default is null. */
	public static function coalescingParameterType(value:CoalescingDefaultValue, t:Type):Type {
		return switch (value) {
			case CNull: t;
			default: withoutNull(t);
		};
	}

	/**
		A local ternary whose sanctioned value is null can be typed by Haxe
		as Null<Null<T>>. Targets need the inner nullable type for that local,
		while a directly declared nullable parameter must keep its one Null<T>
		wrapper for a native null default.
	*/
	public static function coalescingLocalType(value:CoalescingDefaultValue, t:Type):Type {
		return switch (value) {
			case CNull:
				switch (t) {
					case Type.TAbstract(outer, params) if (outer.get().name == "Null" && params.length == 1):
						switch (params[0]) {
							case Type.TAbstract(inner, _) if (inner.get().name == "Null"): params[0];
							default: t;
						}
					case Type.TLazy(resolve): coalescingLocalType(value, resolve());
					default: t;
				}
			default: withoutNull(t);
		};
	}

	static function completeNew(newExpr:TypedExpr, cls:ClassType, args:Array<TypedExpr>, rustTarget:Bool):Void {
		var params:Null<Array<{name:String, opt:Bool, t:Type}>> = null;
		if (cls.constructor != null) {
			final ctorField = cls.constructor.get();
			switch (Context.follow(ctorField.type)) {
				case Type.TFun(argsList, _): params = argsList;
				default:
			}
		}
		if (params == null) return;
		if (args.length >= params.length) return;
		final defaults = lookupFieldDefaults(cls, "new");
		if (defaults == null) return;

		for (i in args.length...params.length) {
			final param = params[i];
			final defVal:Null<DefaultArgValue> = (i < defaults.length) ? defaults[i] : null;
			if (defVal != null) {
				switch (defVal) {
					case VCoalescing(_):
						if (rustTarget) args.push(makeTypedConst(VNull, param.t, newExpr.pos));
					default:
						args.push(makeTypedConst(defVal, param.t, newExpr.pos));
				}
			} else if (param.opt) {
				args.push(makeTypedConst(VNull, param.t, newExpr.pos));
			}
		}
	}

	static function makeTypedConst(defVal:DefaultArgValue, targetType:Type, pos:Position):TypedExpr {
		return switch (defVal) {
			case VInt(v):
				{
					expr: TypedExprDef.TConst(TConstant.TInt(v)),
					pos: pos,
					t: targetType != null ? targetType : Context.getType("Int")
				};
			case VFloat(s):
				{
					expr: TypedExprDef.TConst(TConstant.TFloat(s)),
					pos: pos,
					t: targetType != null ? targetType : Context.getType("Float")
				};
			case VString(s):
				{
					expr: TypedExprDef.TConst(TConstant.TString(s)),
					pos: pos,
					t: targetType != null ? targetType : Context.getType("String")
				};
			case VBool(b):
				{
					expr: TypedExprDef.TConst(TConstant.TBool(b)),
					pos: pos,
					t: targetType != null ? targetType : Context.getType("Bool")
				};
			case VNull:
				{
					expr: TypedExprDef.TConst(TConstant.TNull),
					pos: pos,
					t: targetType != null ? targetType : Context.getType("Dynamic")
				};
			case VEnum(enumRef, enumField):
				final typeExpr:TypedExpr = {
					expr: TypedExprDef.TTypeExpr(ModuleType.TEnumDecl(enumRef)),
					pos: pos,
					t: Context.getType("Dynamic")
				};
				{
					expr: TypedExprDef.TField(typeExpr, FieldAccess.FEnum(enumRef, enumField)),
					pos: pos,
					t: targetType != null ? targetType : Type.TEnum(enumRef, [])
				};
			case VCoalescing(_):
				{
					expr: TypedExprDef.TConst(TConstant.TNull),
					pos: pos,
					t: targetType != null ? targetType : Context.getType("Dynamic")
				};
		};
	}
}
#end
