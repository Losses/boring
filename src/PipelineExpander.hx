#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Position;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.Ref;
import haxe.macro.Type.TVar;
import haxe.macro.Type.TypedExpr;
import haxe.macro.Type.TypedExprDef;

/**
 * Functional idiom expansion pass per docs/specs/macros/01-functional-idiom-expansion.md.
 * Expands map, filter, forEach, associate, sortedBy on Array<T> into loop forms
 * in the typed common layer before target emission.
 */
class PipelineExpander {
	static function substituteLocal(e:TypedExpr, varId:Int, replacement:TypedExpr):Void {
		if (e == null) return;
		switch (e.expr) {
			case TLocal(v) if (v.id == varId):
				replaceExprInPlace(e, replacement);
			default:
				haxe.macro.TypedExprTools.iter(e, child -> substituteLocal(child, varId, replacement));
		}
	}

	static function cleanSyntheticVars(e:TypedExpr, usedNames:Map<String, Bool>):Void {
		if (e == null) return;
		switch (e.expr) {
			case TBlock(stmts):
				var i = 0;
				while (i < stmts.length) {
					switch (stmts[i].expr) {
						case TVar(v, init) if (v.name == "_this" && init != null):
							for (j in (i + 1)...stmts.length) {
								substituteLocal(stmts[j], v.id, init);
							}
							stmts.splice(i, 1);
							continue;
						default:
							cleanSyntheticVars(stmts[i], usedNames);
					}
					i++;
				}
			default:
				haxe.macro.TypedExprTools.iter(e, child -> cleanSyntheticVars(child, usedNames));
		}
	}

	static var varIdCounter:Int = 100000;

	public static function expandModules(modules:Array<haxe.macro.Type.ModuleType>):Void {
		for (index in 0...modules.length) {
			switch (modules[index]) {
				case haxe.macro.Type.ModuleType.TClassDecl(classRef):
					final classType = classRef.get();
					if (!isGuarded(classType.pos)) {
						continue;
					}
					expandClassFields(classType.fields.get());
					expandClassFields(classType.statics.get());
				default:
			}
		}
	}

	static function isGuarded(position:Position):Bool {
		final infos = Context.getPosInfos(position);
		final roots = Intercept.sourceRoots();
		for (index in 0...roots.length) {
			if (StringTools.startsWith(infos.file, roots[index])) {
				return true;
			}
		}
		return false;
	}

	static function expandClassFields(fields:Array<ClassField>):Void {
		for (index in 0...fields.length) {
			final field = fields[index];
			if (field.expr == null) {
				continue;
			}
			final body = field.expr();
			if (body == null) {
				continue;
			}
			if (!isGuarded(body.pos)) {
				continue;
			}
			expandRootExpr(body);
		}
	}

	public static function expandRootExpr(root:TypedExpr):Void {
		final usedNames:Map<String, Bool> = [];
		collectNames(root, usedNames);
		transformExpr(root, usedNames);
	}

	static function collectNames(e:TypedExpr, names:Map<String, Bool>):Void {
		if (e == null) return;
		switch (e.expr) {
			case TVar(v, init):
				names.set(v.name, true);
				if (init != null) collectNames(init, names);
			case TFunction(f):
				for (a in f.args) {
					names.set(a.v.name, true);
				}
				collectNames(f.expr, names);
			default:
				haxe.macro.TypedExprTools.iter(e, child -> collectNames(child, names));
		}
	}

	static function mint(base:String, usedNames:Map<String, Bool>):String {
		if (!usedNames.exists(base)) {
			usedNames.set(base, true);
			return base;
		}
		var suffix = 1;
		while (true) {
			final candidate = base + suffix;
			if (!usedNames.exists(candidate)) {
				usedNames.set(candidate, true);
				return candidate;
			}
			suffix++;
		}
	}

	static function transformExpr(e:TypedExpr, usedNames:Map<String, Bool>):Void {
		if (e == null) return;
		switch (e.expr) {
			case TBlock(stmts):
				transformBlock(stmts, usedNames);
			case TFunction(f):
				transformExpr(f.expr, usedNames);
			case TIf(cond, ifExpr, elseExpr):
				transformExpr(cond, usedNames);
				transformExpr(ifExpr, usedNames);
				if (elseExpr != null) transformExpr(elseExpr, usedNames);
			case TWhile(cond, body, normalWhile):
				transformExpr(cond, usedNames);
				transformExpr(body, usedNames);
			case TFor(v, it, body):
				transformExpr(it, usedNames);
				transformExpr(body, usedNames);
			case TTry(body, catches):
				transformExpr(body, usedNames);
				for (c in catches) transformExpr(c.expr, usedNames);
			case TSwitch(subj, cases, def):
				transformExpr(subj, usedNames);
				for (c in cases) {
					for (v in c.values) transformExpr(v, usedNames);
					transformExpr(c.expr, usedNames);
				}
				if (def != null) transformExpr(def, usedNames);
			case TVar(v, init):
				if (init != null) transformExpr(init, usedNames);
			case TReturn(ret):
				if (ret != null) transformExpr(ret, usedNames);
			default:
				haxe.macro.TypedExprTools.iter(e, child -> transformExpr(child, usedNames));
		}
	}

	static function flattenBlockExprs(stmts:Array<TypedExpr>):Void {
		var i = 0;
		while (i < stmts.length) {
			final stmt = stmts[i];
			if (stmt == null) {
				i++;
				continue;
			}
			switch (stmt.expr) {
				case TBlock(nestedStmts) if (nestedStmts.length > 0):
					stmts.splice(i, 1);
					for (j in 0...nestedStmts.length) {
						stmts.insert(i + j, nestedStmts[j]);
					}
					i += nestedStmts.length - 1;
				case TReturn(ret) if (ret != null):
					switch (ret.expr) {
						case TBlock(innerStmts) if (innerStmts.length > 0):
							final last = innerStmts[innerStmts.length - 1];
							final hoisted = innerStmts.slice(0, innerStmts.length - 1);
							stmt.expr = TReturn(last);
							for (j in 0...hoisted.length) {
								stmts.insert(i + j, hoisted[j]);
							}
							i += hoisted.length;
						default:
					}
				case TVar(v, init) if (init != null):
					switch (init.expr) {
						case TBlock(innerStmts) if (innerStmts.length > 0):
							final last = innerStmts[innerStmts.length - 1];
							final hoisted = innerStmts.slice(0, innerStmts.length - 1);
							stmt.expr = TVar(v, last);
							for (j in 0...hoisted.length) {
								stmts.insert(i + j, hoisted[j]);
							}
							i += hoisted.length;
						default:
					}
				default:
			}
			i++;
		}
	}

	static function transformBlock(stmts:Array<TypedExpr>, usedNames:Map<String, Bool>):Void {
		var i = 0;
		while (i < stmts.length) {
			final stmt = stmts[i];
			if (stmt == null) {
				i++;
				continue;
			}
			transformInnerBlocks(stmt, usedNames);

			final expansions = findAndExpandPipelines(stmt, usedNames);
			if (expansions != null && expansions.length > 0) {
				for (j in 0...expansions.length) {
					stmts.insert(i + j, expansions[j]);
				}
				i += expansions.length;
			}
			i++;
		}
		flattenBlockExprs(stmts);
	}

	static function transformInnerBlocks(e:TypedExpr, usedNames:Map<String, Bool>):Void {
		if (e == null) return;
		switch (e.expr) {
			case TBlock(stmts):
				transformBlock(stmts, usedNames);
			case TIf(cond, ifExpr, elseExpr):
				transformInnerBlocks(cond, usedNames);
				transformInnerBlocks(ifExpr, usedNames);
				if (elseExpr != null) transformInnerBlocks(elseExpr, usedNames);
			case TWhile(cond, body, normalWhile):
				transformInnerBlocks(cond, usedNames);
				transformInnerBlocks(body, usedNames);
			case TFor(v, it, body):
				transformInnerBlocks(it, usedNames);
				transformInnerBlocks(body, usedNames);
			case TTry(body, catches):
				transformInnerBlocks(body, usedNames);
				for (c in catches) transformInnerBlocks(c.expr, usedNames);
			case TSwitch(subj, cases, def):
				transformInnerBlocks(subj, usedNames);
				for (c in cases) {
					for (v in c.values) transformInnerBlocks(v, usedNames);
					transformInnerBlocks(c.expr, usedNames);
				}
				if (def != null) transformInnerBlocks(def, usedNames);
			case TFunction(f):
				transformInnerBlocks(f.expr, usedNames);
			default:
		}
	}

	static function findAndExpandPipelines(stmt:TypedExpr, usedNames:Map<String, Bool>):Null<Array<TypedExpr>> {
		if (stmt == null) return null;
		validatePipelinePositions(stmt, isDirectStatement(stmt));

		final generatedStmts:Array<TypedExpr> = [];
		var changed = false;

		while (true) {
			final pipeline = findPipelineCall(stmt);
			if (pipeline == null) {
				break;
			}
			changed = true;
			final expansion = expandPipeline(pipeline, stmt, usedNames);
			for (s in expansion.stmts) {
				generatedStmts.push(s);
			}
			if (pipeline.kind == "forEach" && isPureCallStmt(stmt, pipeline.callExpr)) {
				if (expansion.stmts.length > 0) {
					final lastStmt = expansion.stmts[expansion.stmts.length - 1];
					stmt.expr = lastStmt.expr;
					stmt.pos = lastStmt.pos;
					stmt.t = lastStmt.t;
					generatedStmts.pop();
				}
			} else if (expansion.replacement != null) {
				replaceExprInPlace(pipeline.callExpr, expansion.replacement);
			}
			cleanSyntheticVars(stmt, usedNames);
		}

		return changed ? generatedStmts : null;
	}

	static function isPureCallStmt(stmt:TypedExpr, callExpr:TypedExpr):Bool {
		if (stmt == callExpr) return true;
		return switch (stmt.expr) {
			case TParenthesis(inner), TCast(inner, _), TMeta(_, inner):
				isPureCallStmt(inner, callExpr);
			default: false;
		};
	}

	static function isDirectStatement(e:TypedExpr):Bool {
		if (e == null) return false;
		if (parsePipelineCall(e) != null) return true;
		return switch (e.expr) {
			case TVar(_, _): true;
			case TReturn(_): true;
			case TCall(_, _): true;
			default: false;
		};
	}

	static function validatePipelinePositions(e:TypedExpr, isDirect:Bool):Void {
		if (e == null) return;
		final p = parsePipelineCall(e);
		if (p != null) {
			if (!isDirect) {
				Context.fatalError("collection pipeline calls expand in direct statement positions only", e.pos);
			}
			validatePipelinePositions(p.receiver, true);
			return;
		}
		switch (e.expr) {
			case TBlock(stmts):
				for (idx in 0...stmts.length) {
					final isLast = (idx == stmts.length - 1);
					validatePipelinePositions(stmts[idx], isLast ? isDirect : isDirectStatement(stmts[idx]));
				}
			case TVar(v, init):
				if (init != null) {
					final isPure = isSideEffectFree(init);
					validatePipelinePositions(init, isPure || parsePipelineCall(init) != null);
				}
			case TReturn(ret):
				if (ret != null) {
					final isPure = isSideEffectFree(ret);
					validatePipelinePositions(ret, isPure || parsePipelineCall(ret) != null);
				}
			case TCall(fn, args):
				for (a in args) validatePipelinePositions(a, false);
			case TBinop(op, e1, e2):
				validatePipelinePositions(e1, false);
				validatePipelinePositions(e2, false);
			case TUnop(_, _, inner):
				validatePipelinePositions(inner, false);
			case TArray(arr, idx):
				validatePipelinePositions(arr, false);
				validatePipelinePositions(idx, false);
			case TArrayDecl(elems):
				for (elem in elems) validatePipelinePositions(elem, false);
			case TObjectDecl(fields):
				for (f in fields) validatePipelinePositions(f.expr, false);
			default:
				haxe.macro.TypedExprTools.iter(e, child -> validatePipelinePositions(child, false));
		}
	}

	static function isSideEffectFree(e:TypedExpr):Bool {
		if (e == null) return true;
		if (parsePipelineCall(e) != null) return true;
		return switch (e.expr) {
			case TConst(_): true;
			case TLocal(_): true;
			case TTypeExpr(_): true;
			case TParenthesis(inner), TMeta(_, inner), TCast(inner, _):
				isSideEffectFree(inner);
			case TField(subj, _):
				isSideEffectFree(subj);
			case TArray(subj, idx):
				isSideEffectFree(subj) && isSideEffectFree(idx);
			case TBlock(stmts):
				var ok = true;
				for (s in stmts) if (!isSideEffectFree(s)) ok = false;
				ok;
			case TVar(v, init):
				init == null || isSideEffectFree(init);
			case TReturn(ret):
				ret == null || isSideEffectFree(ret);
			case TBinop(op, e1, e2):
				switch (op) {
					case OpAssign, OpAssignOp(_): false;
					default: isSideEffectFree(e1) && isSideEffectFree(e2);
				}
			case TUnop(op, _, inner):
				switch (op) {
					case OpIncrement, OpDecrement: false;
					default: isSideEffectFree(inner);
				}
			case TArrayDecl(elems):
				var ok = true;
				for (elem in elems) if (!isSideEffectFree(elem)) ok = false;
				ok;
			case TObjectDecl(fields):
				var ok = true;
				for (f in fields) if (!isSideEffectFree(f.expr)) ok = false;
				ok;
			default: false;
		};
	}

	static function findPipelineCall(e:TypedExpr):Null<PipelineCall> {
		if (e == null) return null;
		var found:Null<PipelineCall> = null;

		function search(node:TypedExpr):Void {
			if (node == null || found != null) return;
			final p = parsePipelineCall(node);
			if (p != null) {
				final innerPipeline = findPipelineCall(p.receiver);
				if (innerPipeline != null) {
					found = innerPipeline;
					return;
				}
				found = p;
				return;
			}
			switch (node.expr) {
				case TWhile(_, _, _) | TFor(_, _, _) | TIf(_, _, _) | TFunction(_) | TTry(_, _):
					return;
				case TCall(fn, args):
					search(fn);
					for (a in args) search(a);
				case TBlock(stmts):
					for (s in stmts) search(s);
				default:
					haxe.macro.TypedExprTools.iter(node, search);
			}
		}

		search(e);
		return found;
	}

	static function parsePipelineCall(e:TypedExpr):Null<PipelineCall> {
		if (e == null) return null;

		switch (e.expr) {
			case TCall(fn, args):
				switch (fn.expr) {
					case TField(receiver, FInstance(c, _, cf)):
						final name = cf.get().name;
						if (isArrayType(receiver.t) && (name == "map" || name == "filter")) {
							if (args.length != 1) {
								Context.fatalError("collection pipeline methods accept inline function literals only", e.pos);
							}
							return {
								kind: name,
								receiver: receiver,
								lambdaExpr: args[0],
								callExpr: e,
								pos: e.pos
							};
						}
					case TField(staticSubj, FStatic(c, cf)):
						final name = cf.get().name;
						final cls = c.get();
						final isFunctional = cls.name == "Functional" || cls.pack.join(".") == "std.Functional" || cls.module == "std.Functional";
						if (isFunctional && isClosedListStatic(name)) {
							if (args.length != 2) {
								Context.fatalError("collection pipeline methods accept inline function literals only", e.pos);
							}
							if (isArrayType(args[0].t)) {
								return {
									kind: name,
									receiver: args[0],
									lambdaExpr: args[1],
									callExpr: e,
									pos: e.pos
								};
							}
						}
					default:
				}
			default:
		}

		return parseInlinedArrayMethod(e);
	}

	static function isClosedListStatic(name:String):Bool {
		return name == "forEach"
			|| name == "associate"
			|| name == "sortedBy"
			|| name == "any"
			|| name == "all"
			|| name == "firstOrNull"
			|| name == "sumOfInt"
			|| name == "sumOfFloat"
			|| name == "mapNotNull"
			|| name == "flatMap"
			|| name == "groupBy";
	}

	static function fieldName(fa:FieldAccess):String {
		return switch (fa) {
			case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf) | FClosure(_, cf): cf.get().name;
			case FEnum(_, ef): ef.name;
			case FDynamic(n): n;
		};
	}

	static function stripWrap(e:TypedExpr):TypedExpr {
		if (e == null) return null;
		return switch (e.expr) {
			case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): stripWrap(inner);
			default: e;
		};
	}

	static function parseInlinedArrayMethod(e:TypedExpr):Null<PipelineCall> {
		if (e == null) return null;
		switch (e.expr) {
			case TBlock(stmts) if (stmts.length == 3):
				if (stmts[0] == null || stmts[1] == null || stmts[2] == null) return null;
				final resultVar = switch (stmts[0].expr) {
					case TVar(v, _): v;
					default: null;
				};
				if (resultVar == null) return null;
				switch (stmts[1].expr) {
					case TBlock(innerStmts) if (innerStmts.length >= 2):
						var receiverExpr:Null<TypedExpr> = null;
						for (st in innerStmts) {
							if (st == null) continue;
							switch (st.expr) {
								case TVar(v, init) if (init != null):
									if (v.name == "_this" || isArrayType(init.t)) {
										receiverExpr = init;
									} else {
										switch (stripWrap(init).expr) {
											case TField(subj, fa) if (fieldName(fa) == "length" && isArrayType(subj.t)):
												receiverExpr = subj;
											default:
										}
									}
								default:
							}
						}
						final whileExpr = innerStmts[innerStmts.length - 1];
						if (whileExpr == null) return null;
						switch (whileExpr.expr) {
							case TWhile(cond, whileBody, _):
								if (receiverExpr == null && cond != null) {
									switch (stripWrap(cond).expr) {
										case TBinop(OpLt, _, r):
											switch (stripWrap(r).expr) {
												case TField(subj, fa) if (fieldName(fa) == "length"):
													receiverExpr = subj;
												default:
											}
										default:
									}
								}
								if (receiverExpr != null) {
									switch (stripWrap(receiverExpr).expr) {
										case TLocal(v):
											for (st in innerStmts) {
												if (st == null) continue;
												switch (st.expr) {
													case TVar(tv, init) if (tv.id == v.id && init != null):
														receiverExpr = init;
														break;
													default:
												}
											}
										default:
									}
								}
								if (receiverExpr == null || !isArrayType(receiverExpr.t)) return null;
								return findLambdaInInlinedLoop(whileBody, receiverExpr, e);
							default: return null;
						}
					default: return null;
				}
			default: return null;
		}
	}

	static function findLambdaInInlinedLoop(whileBody:TypedExpr, receiverExpr:TypedExpr, topBlock:TypedExpr):Null<PipelineCall> {
		if (whileBody == null) return null;
		switch (whileBody.expr) {
			case TBlock(bodyStmts):
				var elementVar:Null<TVar> = null;
				for (s in bodyStmts) {
					if (s == null) continue;
					switch (s.expr) {
						case TVar(v, _):
							elementVar = v;
						case TBinop(OpAssign, target, valExpr):
							switch (stripWrap(target).expr) {
								case TArray(_, _):
									switch (valExpr.expr) {
										case TCall(innerFn, _) if (innerFn != null):
											switch (innerFn.expr) {
												case TFunction(_):
													return {
														kind: "map",
														receiver: receiverExpr,
														lambdaExpr: innerFn,
														callExpr: topBlock,
														pos: topBlock.pos
													};
												default:
											}
										default:
									}
									if (elementVar != null) {
										final synFn:TypedExpr = {
											expr: TFunction({
												args: [{ v: elementVar, value: null }],
												t: valExpr.t,
												expr: valExpr
											}),
											pos: topBlock.pos,
											t: TFun([ { name: elementVar.name, opt: false, t: elementVar.t } ], valExpr.t)
										};
										return {
											kind: "map",
											receiver: receiverExpr,
											lambdaExpr: synFn,
											callExpr: topBlock,
											pos: topBlock.pos
										};
									}
								default:
							}
						case TCall(fn, args):
							final isPush = switch (fn.expr) {
								case TField(_, FInstance(c, _, cf)): cf.get().name == "push";
								default: false;
							};
							if (isPush && args.length == 1 && args[0] != null && elementVar != null) {
								final argExpr = args[0];
								switch (argExpr.expr) {
									case TCall(innerFn, _) if (innerFn != null):
										switch (innerFn.expr) {
											case TFunction(_):
												return {
													kind: "map",
													receiver: receiverExpr,
													lambdaExpr: innerFn,
													callExpr: topBlock,
													pos: topBlock.pos
												};
											default:
										}
									default:
								}
								final synFn:TypedExpr = {
									expr: TFunction({
										args: [{ v: elementVar, value: null }],
										t: argExpr.t,
										expr: argExpr
									}),
									pos: topBlock.pos,
									t: TFun([ { name: elementVar.name, opt: false, t: elementVar.t } ], argExpr.t)
								};
								return {
									kind: "map",
									receiver: receiverExpr,
									lambdaExpr: synFn,
									callExpr: topBlock,
									pos: topBlock.pos
								};
							}
						case TIf(cond, thenExpr, elseExpr) if (elseExpr == null):
							if (cond != null && elementVar != null) {
								final isPush = switch (thenExpr.expr) {
									case TBlock(thStmts) if (thStmts.length == 1):
										switch (thStmts[0].expr) {
											case TCall(fn, _):
												switch (fn.expr) {
													case TField(_, FInstance(c, _, cf)): cf.get().name == "push";
													default: false;
												}
											default: false;
										}
									case TCall(fn, _):
										switch (fn.expr) {
											case TField(_, FInstance(c, _, cf)): cf.get().name == "push";
											default: false;
										}
									default: false;
								};
								if (!isPush) continue;
								switch (cond.expr) {
									case TCall(innerFn, _) if (innerFn != null):
										switch (innerFn.expr) {
											case TFunction(_):
												return {
													kind: "filter",
													receiver: receiverExpr,
													lambdaExpr: innerFn,
													callExpr: topBlock,
													pos: topBlock.pos
												};
											default:
										}
									default:
								}
								final synFn:TypedExpr = {
									expr: TFunction({
										args: [{ v: elementVar, value: null }],
										t: cond.t,
										expr: cond
									}),
									pos: topBlock.pos,
									t: TFun([ { name: elementVar.name, opt: false, t: elementVar.t } ], cond.t)
								};
								return {
									kind: "filter",
									receiver: receiverExpr,
									lambdaExpr: synFn,
									callExpr: topBlock,
									pos: topBlock.pos
								};
							}
						default:
					}
				}
			default:
		}
		return null;
	}

	static function isArrayType(t:Type):Bool {
		if (t == null) return false;
		return switch (Context.follow(t)) {
			case TInst(c, params):
				c.get().name == "Array" && c.get().pack.length == 0 && params.length == 1;
			default: false;
		};
	}

	static function getArrayElemType(t:Type):Type {
		return switch (Context.follow(t)) {
			case TInst(c, params): params[0];
			default: Context.getType("Dynamic");
		};
	}

	static function validateLambda(lambdaExpr:TypedExpr):{v:TVar, expr:TypedExpr, retType:Type} {
		final func = switch (lambdaExpr.expr) {
			case TFunction(f): f;
			case TParenthesis(inner):
				switch (inner.expr) {
					case TFunction(f): f;
					default: null;
				}
			default: null;
		};
		if (func == null || func.args.length != 1) {
			Context.fatalError("collection pipeline methods accept inline function literals only", lambdaExpr.pos);
		}

		var hasNestedFun = false;
		function checkFun(node:TypedExpr):Void {
			if (node == null) return;
			switch (node.expr) {
				case TFunction(_): hasNestedFun = true;
				default: haxe.macro.TypedExprTools.iter(node, checkFun);
			}
		}
		haxe.macro.TypedExprTools.iter(func.expr, checkFun);
		if (hasNestedFun) {
			Context.fatalError("collection pipeline methods accept inline function literals only", lambdaExpr.pos);
		}

		return {v: func.args[0].v, expr: func.expr, retType: func.t};
	}

	static function expandPipeline(p:PipelineCall, enclosingStmt:TypedExpr, usedNames:Map<String, Bool>):{stmts:Array<TypedExpr>, replacement:Null<TypedExpr>} {
		final lambda = validateLambda(p.lambdaExpr);
		final elemType = getArrayElemType(p.receiver.t);
		final pos = p.pos;

		switch (p.kind) {
			case "map":
				final resultName = mint("pipeline_result", usedNames);
				final retType = lambda.retType;
				final arrayType = makeArrayType(retType);

				final resultVar = makeTVar(resultName, arrayType, true);
				final resultDecl = makeTVarStmt(resultVar, makeNewArray(retType, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, retVal -> {
					makeArrayStore(makeLocal(resultVar, pos), makeLocal(indexVar, pos), retVal, pos);
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "filter":
				final resultName = mint("pipeline_result", usedNames);
				final arrayType = makeArrayType(elemType);

				final resultVar = makeTVar(resultName, arrayType, true);
				final resultDecl = makeTVarStmt(resultVar, makeNewArray(elemType, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, predVal -> {
					final pushCall = makeArrayPush(makeLocal(resultVar, pos), makeLocal(lambda.v, pos), elemType, pos);
					{
						expr: TIf(predVal, pushCall, null),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "forEach":
				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, retVal -> retVal);

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [initCounter, initBound, whileLoop],
					replacement: makeIntConst(0, pos)
				};

			case "associate":
				final entryType = lambda.retType;
				final keyType = extractStructFieldType(entryType, "key", pos);
				final valType = extractStructFieldType(entryType, "value", pos);

				final builderName = mint("pipeline_builder", usedNames);
				final resultName = mint("pipeline_result", usedNames);
				final entryName = mint("pipeline_entry", usedNames);

				final builderType = makeSortedMapBuilderType(keyType, valType);
				final sortedMapType = makeSortedMapType(keyType, valType);

				final builderVar = makeTVar(builderName, builderType, true);
				final builderDecl = makeTVarStmt(builderVar, makeSortedMapBuilderCall(keyType, valType, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);

				final bodyStmts = adaptLambdaBody(lambda.expr, entryVal -> {
					var keyExpr:Null<TypedExpr> = null;
					var valExpr:Null<TypedExpr> = null;
					switch (entryVal.expr) {
						case TObjectDecl(fields):
							for (f in fields) {
								if (f.name == "key") keyExpr = f.expr;
								if (f.name == "value") valExpr = f.expr;
							}
						default:
					}
					if (keyExpr != null && valExpr != null) {
						makeSortedMapPutCall(makeLocal(builderVar, pos), keyExpr, valExpr, pos);
					} else {
						final entryVar = makeTVar(entryName, entryType, true);
						final entryDecl = makeTVarStmt(entryVar, entryVal, pos);
						final putCall = makeSortedMapPutCall(makeLocal(builderVar, pos), makeFieldRead(makeLocal(entryVar, pos), "key", keyType, pos), makeFieldRead(makeLocal(entryVar, pos), "value", valType, pos), pos);
						{
							expr: TBlock([entryDecl, putCall]),
							pos: pos,
							t: Context.getType("Void")
						};
					}
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);

				final resultVar = makeTVar(resultName, sortedMapType, true);
				final resultDecl = makeTVarStmt(resultVar, makeSortedMapBuildCall(makeLocal(builderVar, pos), sortedMapType, pos), pos);

				return {
					stmts: [builderDecl, initCounter, initBound, whileLoop, resultDecl],
					replacement: makeLocal(resultVar, pos)
				};

			case "sortedBy":
				final resultName = mint("pipeline_result", usedNames);
				final arrayType = makeArrayType(elemType);
				final resultVar = makeTVar(resultName, arrayType, true);

				final callExpr = p.callExpr;
				final callClone:TypedExpr = {
					expr: switch (callExpr.expr) {
						case TCall(fn, args): TCall(fn, args.copy());
						default: callExpr.expr;
					},
					pos: callExpr.pos,
					t: callExpr.t
				};
				final resultDecl = makeTVarStmt(resultVar, callClone, pos);

				return {
					stmts: [resultDecl],
					replacement: makeLocal(resultVar, pos)
				};

			case "any":
				final resultName = mint("pipeline_result", usedNames);
				final boolType = Context.getType("Bool");
				final resultVar = makeTVar(resultName, boolType, false);
				final resultDecl = makeTVarStmt(resultVar, makeBoolConst(false, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, predVal -> {
					final assignTrue = {
						expr: TBinop(OpAssign, makeLocal(resultVar, pos), makeBoolConst(true, pos)),
						pos: pos,
						t: boolType
					};
					final breakStmt = makeBreak(pos);
					final thenBlock = {
						expr: TBlock([assignTrue, breakStmt]),
						pos: pos,
						t: Context.getType("Void")
					};
					{
						expr: TIf(predVal, thenBlock, null),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "all":
				final resultName = mint("pipeline_result", usedNames);
				final boolType = Context.getType("Bool");
				final resultVar = makeTVar(resultName, boolType, false);
				final resultDecl = makeTVarStmt(resultVar, makeBoolConst(true, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, predVal -> {
					final assignFalse = {
						expr: TBinop(OpAssign, makeLocal(resultVar, pos), makeBoolConst(false, pos)),
						pos: pos,
						t: boolType
					};
					final breakStmt = makeBreak(pos);
					final thenBlock = {
						expr: TBlock([assignFalse, breakStmt]),
						pos: pos,
						t: Context.getType("Void")
					};
					{
						expr: TIf(makeNot(predVal, pos), thenBlock, null),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "firstOrNull":
				final resultName = mint("pipeline_result", usedNames);
				final nullElemType = makeNullType(elemType);
				final resultVar = makeTVar(resultName, nullElemType, false);
				final resultDecl = makeTVarStmt(resultVar, makeNullConst(pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, predVal -> {
					final assignItem = {
						expr: TBinop(OpAssign, makeLocal(resultVar, pos), makeLocal(lambda.v, pos)),
						pos: pos,
						t: elemType
					};
					final breakStmt = makeBreak(pos);
					final thenBlock = {
						expr: TBlock([assignItem, breakStmt]),
						pos: pos,
						t: Context.getType("Void")
					};
					{
						expr: TIf(predVal, thenBlock, null),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "sumOfInt":
				final resultName = mint("pipeline_result", usedNames);
				final intType = Context.getType("Int");
				final resultVar = makeTVar(resultName, intType, false);
				final resultDecl = makeTVarStmt(resultVar, makeIntConst(0, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, intVal -> {
					{
						expr: TBinop(OpAssignOp(OpAdd), makeLocal(resultVar, pos), intVal),
						pos: pos,
						t: intType
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "sumOfFloat":
				final resultName = mint("pipeline_result", usedNames);
				final floatType = Context.getType("Float");
				final resultVar = makeTVar(resultName, floatType, false);
				final resultDecl = makeTVarStmt(resultVar, makeFloatConst(0.0, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);
				final bodyStmts = adaptLambdaBody(lambda.expr, floatVal -> {
					{
						expr: TBinop(OpAssignOp(OpAdd), makeLocal(resultVar, pos), floatVal),
						pos: pos,
						t: floatType
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "mapNotNull":
				final resultName = mint("pipeline_result", usedNames);
				final retType = lambda.retType;
				final innerRetType = unwrapNullType(retType);
				final arrayType = makeArrayType(innerRetType);

				final resultVar = makeTVar(resultName, arrayType, true);
				final resultDecl = makeTVarStmt(resultVar, makeNewArray(innerRetType, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);

				final bodyStmts = adaptLambdaBody(lambda.expr, mappedVal -> {
					final mappedItemName = mint("pipeline_item", usedNames);
					final mappedItemVar = makeTVar(mappedItemName, retType, true);
					final mappedItemDecl = makeTVarStmt(mappedItemVar, mappedVal, pos);
					final pushCall = makeArrayPush(makeLocal(resultVar, pos), makeLocal(mappedItemVar, pos), innerRetType, pos);
					final ifNonNull = {
						expr: TIf(makeNonNullCheck(makeLocal(mappedItemVar, pos), pos), pushCall, null),
						pos: pos,
						t: Context.getType("Void")
					};
					{
						expr: TBlock([mappedItemDecl, ifNonNull]),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "flatMap":
				if (!isArrayType(lambda.retType)) {
					Context.fatalError("flat map selectors return arrays only", p.lambdaExpr.pos);
				}
				final innerElemType = getArrayElemType(lambda.retType);
				final resultName = mint("pipeline_result", usedNames);
				final arrayType = makeArrayType(innerElemType);

				final resultVar = makeTVar(resultName, arrayType, true);
				final resultDecl = makeTVarStmt(resultVar, makeNewArray(innerElemType, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);

				final bodyStmts = adaptLambdaBody(lambda.expr, innerArrVal -> {
					final innerArrName = mint("pipeline_inner", usedNames);
					final innerArrVar = makeTVar(innerArrName, lambda.retType, true);
					final innerArrDecl = makeTVarStmt(innerArrVar, innerArrVal, pos);

					final innerIndexName = mint("pipeline_index", usedNames);
					final innerCounterVar = makeTVar("_g", Context.getType("Int"), false);
					final innerBoundVar = makeTVar("_g1", Context.getType("Int"), true);
					final innerIndexVar = makeTVar(innerIndexName, Context.getType("Int"), true);

					final innerInitCounter = makeTVarStmt(innerCounterVar, makeIntConst(0, pos), pos);
					final innerInitBound = makeTVarStmt(innerBoundVar, makeArrayLength(makeLocal(innerArrVar, pos), pos), pos);

					final innerItemRead = makeArrayRead(makeLocal(innerArrVar, pos), makeLocal(innerIndexVar, pos), innerElemType, pos);
					final innerPush = makeArrayPush(makeLocal(resultVar, pos), innerItemRead, innerElemType, pos);

					final innerLoop = makeIntervalLoop(innerCounterVar, innerBoundVar, innerIndexVar, [innerPush], pos);

					{
						expr: TBlock([innerArrDecl, innerInitCounter, innerInitBound, innerLoop]),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);
				return {
					stmts: [resultDecl, initCounter, initBound, whileLoop],
					replacement: makeLocal(resultVar, pos)
				};

			case "groupBy":
				final entryType = lambda.retType;
				final keyType = extractStructFieldType(entryType, "key", pos);
				final valType = extractStructFieldType(entryType, "value", pos);
				final valArrayType = makeArrayType(valType);

				final builderName = mint("pipeline_builder", usedNames);
				final resultName = mint("pipeline_result", usedNames);
				final entryName = mint("pipeline_entry", usedNames);
				final bucketName = mint("pipeline_bucket", usedNames);

				final builderType = makeSortedMapBuilderType(keyType, valArrayType);
				final sortedMapType = makeSortedMapType(keyType, valArrayType);

				final builderVar = makeTVar(builderName, builderType, true);
				final builderDecl = makeTVarStmt(builderVar, makeSortedMapBuilderCall(keyType, valArrayType, pos), pos);

				final indexName = mint("pipeline_index", usedNames);
				final counterVar = makeTVar("_g", Context.getType("Int"), false);
				final boundVar = makeTVar("_g1", Context.getType("Int"), true);
				final indexVar = makeTVar(indexName, Context.getType("Int"), true);

				final initCounter = makeTVarStmt(counterVar, makeIntConst(0, pos), pos);
				final initBound = makeTVarStmt(boundVar, makeArrayLength(p.receiver, pos), pos);

				final itemDecl = makeTVarStmt(lambda.v, makeArrayRead(p.receiver, makeLocal(indexVar, pos), elemType, pos), pos);

				final bodyStmts = adaptLambdaBody(lambda.expr, entryVal -> {
					final entryVar = makeTVar(entryName, entryType, true);
					final entryDecl = makeTVarStmt(entryVar, entryVal, pos);

					final keyRead = makeFieldRead(makeLocal(entryVar, pos), "key", keyType, pos);
					final valRead = makeFieldRead(makeLocal(entryVar, pos), "value", valType, pos);

					final bucketVar = makeTVar(bucketName, valArrayType, false);
					final getBucketCall = makeSortedMapGetCall(makeLocal(builderVar, pos), keyRead, valArrayType, pos);
					final bucketDecl = makeTVarStmt(bucketVar, getBucketCall, pos);

					final cond = makeNullCheck(makeLocal(bucketVar, pos), pos);
					final allocBucket = {
						expr: TBinop(OpAssign, makeLocal(bucketVar, pos), makeNewArray(valType, pos)),
						pos: pos,
						t: valArrayType
					};
					final putCall = makeSortedMapPutCall(makeLocal(builderVar, pos), keyRead, makeLocal(bucketVar, pos), pos);
					final ifNullBlock = {
						expr: TBlock([allocBucket, putCall]),
						pos: pos,
						t: Context.getType("Void")
					};
					final ifStmt = {
						expr: TIf(cond, ifNullBlock, null),
						pos: pos,
						t: Context.getType("Void")
					};

					final pushCall = makeArrayPush(makeLocal(bucketVar, pos), valRead, valType, pos);

					{
						expr: TBlock([entryDecl, bucketDecl, ifStmt, pushCall]),
						pos: pos,
						t: Context.getType("Void")
					};
				});

				final whileLoop = makeIntervalLoop(counterVar, boundVar, indexVar, [itemDecl].concat(bodyStmts), pos);

				final resultVar = makeTVar(resultName, sortedMapType, true);
				final resultDecl = makeTVarStmt(resultVar, makeSortedMapBuildCall(makeLocal(builderVar, pos), sortedMapType, pos), pos);

				return {
					stmts: [builderDecl, initCounter, initBound, whileLoop, resultDecl],
					replacement: makeLocal(resultVar, pos)
				};

			default:
				throw "Unknown pipeline kind: " + p.kind;
		}
	}

	static function adaptLambdaBody(body:TypedExpr, wrapResult:TypedExpr->TypedExpr):Array<TypedExpr> {
		switch (body.expr) {
			case TBlock(stmts):
				if (stmts.length == 0) {
					return [wrapResult(body)];
				}
				final out = stmts.slice(0, stmts.length - 1);
				final last = stmts[stmts.length - 1];
				switch (last.expr) {
					case TReturn(maybeExpr):
						if (maybeExpr != null) {
							out.push(wrapResult(maybeExpr));
						} else {
							out.push(wrapResult(last));
						}
					default:
						out.push(wrapResult(last));
				}
				return out;
			case TReturn(maybeExpr):
				return [wrapResult(maybeExpr != null ? maybeExpr : body)];
			default:
				return [wrapResult(body)];
		}
	}

	static function extractStructFieldType(t:Type, fieldName:String, pos:Position):Type {
		switch (Context.follow(t)) {
			case TAnonymous(anon):
				for (f in anon.get().fields) {
					if (f.name == fieldName) {
						return f.type;
					}
				}
				Context.fatalError("associate lambda body structure missing field " + fieldName, pos);
				return Context.getType("Dynamic");
			default:
				Context.fatalError("associate lambda body must be a structure literal with key and value fields", pos);
				return Context.getType("Dynamic");
		}
	}

	static function makeBoolConst(val:Bool, pos:Position):TypedExpr {
		return {
			expr: TConst(TBool(val)),
			pos: pos,
			t: Context.getType("Bool")
		};
	}

	static function makeFloatConst(val:Float, pos:Position):TypedExpr {
		final s = Std.string(val);
		final str = s.indexOf(".") >= 0 ? s : s + ".0";
		return {
			expr: TConst(TFloat(str)),
			pos: pos,
			t: Context.getType("Float")
		};
	}

	static function makeNullConst(pos:Position):TypedExpr {
		return {
			expr: TConst(TNull),
			pos: pos,
			t: Context.getType("Dynamic")
		};
	}

	static function makeBreak(pos:Position):TypedExpr {
		return {
			expr: TBreak,
			pos: pos,
			t: Context.getType("Void")
		};
	}

	static function makeNot(e:TypedExpr, pos:Position):TypedExpr {
		return {
			expr: TUnop(OpNot, false, {
				expr: TParenthesis(e),
				pos: pos,
				t: e.t
			}),
			pos: pos,
			t: Context.getType("Bool")
		};
	}

	static function unwrapNullType(t:Type):Type {
		if (t == null) return t;
		return switch (t) {
			case TAbstract(a, params) if (a.get().name == "Null"):
				unwrapNullType(params[0]);
			case TType(def, params):
				unwrapNullType(Context.follow(t));
			default:
				switch (Context.follow(t)) {
					case TAbstract(a, params) if (a.get().name == "Null"):
						unwrapNullType(params[0]);
					default: t;
				}
		};
	}

	static function makeNullType(elemType:Type):Type {
		final nullAbstract = switch (Context.getType("Null")) {
			case TAbstract(a, _): a;
			default: throw "Null abstract type not found";
		};
		return TAbstract(nullAbstract, [elemType]);
	}

	static function makeNullCheck(e:TypedExpr, pos:Position):TypedExpr {
		return {
			expr: TBinop(OpEq, e, makeNullConst(pos)),
			pos: pos,
			t: Context.getType("Bool")
		};
	}

	static function makeNonNullCheck(e:TypedExpr, pos:Position):TypedExpr {
		return {
			expr: TBinop(OpNotEq, e, makeNullConst(pos)),
			pos: pos,
			t: Context.getType("Bool")
		};
	}

	static function makeSortedMapGetCall(builderLocal:TypedExpr, keyExpr:TypedExpr, valType:Type, pos:Position):TypedExpr {
		final builderClassRef = getSortedMapBuilderClassRef();
		var getField:Null<ClassField> = null;
		for (f in builderClassRef.get().fields.get()) {
			if (f.name == "get") {
				getField = f;
				break;
			}
		}
		if (getField == null) {
			throw "SortedMapBuilder.get method not found";
		}
		final nullValType = makeNullType(valType);
		final getFieldExpr:TypedExpr = {
			expr: TField(builderLocal, FInstance(builderClassRef, [keyExpr.t, valType], makeRef(getField))),
			pos: pos,
			t: TFun([{name: "key", opt: false, t: keyExpr.t}], nullValType)
		};
		return {
			expr: TCall(getFieldExpr, [keyExpr]),
			pos: pos,
			t: nullValType
		};
	}

	static function makeRef<T>(val:T):Ref<T> {
		return {
			get: () -> val,
			toString: () -> Std.string(val)
		};
	}

	static function makeTVar(name:String, t:Type, isFinal:Bool):TVar {
		return {
			id: varIdCounter++,
			name: name,
			t: t,
			capture: false,
			extra: null,
			meta: null,
			isStatic: false
		};
	}

	static function makeLocal(v:TVar, pos:Position):TypedExpr {
		return {
			expr: TLocal(v),
			pos: pos,
			t: v.t
		};
	}

	static function makeTVarStmt(v:TVar, init:Null<TypedExpr>, pos:Position):TypedExpr {
		return {
			expr: TVar(v, init),
			pos: pos,
			t: Context.getType("Void")
		};
	}

	static function makeIntConst(val:Int, pos:Position):TypedExpr {
		return {
			expr: TConst(TInt(val)),
			pos: pos,
			t: Context.getType("Int")
		};
	}

	static function makeArrayType(elemType:Type):Type {
		final arrayClassRef = switch (Context.getType("Array")) {
			case TInst(c, _): c;
			default: throw "Array type not found";
		};
		return TInst(arrayClassRef, [elemType]);
	}

	static function makeNewArray(elemType:Type, pos:Position):TypedExpr {
		final arrayClassRef = switch (Context.getType("Array")) {
			case TInst(c, _): c;
			default: throw "Array type not found";
		};
		return {
			expr: TNew(arrayClassRef, [elemType], []),
			pos: pos,
			t: TInst(arrayClassRef, [elemType])
		};
	}

	static function makeArrayLength(receiver:TypedExpr, pos:Position):TypedExpr {
		final arrayClassRef = switch (Context.getType("Array")) {
			case TInst(c, _): c;
			default: throw "Array type not found";
		};
		final elemType = getArrayElemType(receiver.t);
		var lengthField:Null<ClassField> = null;
		for (f in arrayClassRef.get().fields.get()) {
			if (f.name == "length") {
				lengthField = f;
				break;
			}
		}
		return {
			expr: TField(receiver, FInstance(arrayClassRef, [elemType], makeRef(lengthField))),
			pos: pos,
			t: Context.getType("Int")
		};
	}

	static function makeArrayRead(receiver:TypedExpr, indexLocal:TypedExpr, elemType:Type, pos:Position):TypedExpr {
		return {
			expr: TArray(receiver, indexLocal),
			pos: pos,
			t: elemType
		};
	}

	static function makeArrayStore(arrayLocal:TypedExpr, indexLocal:TypedExpr, valExpr:TypedExpr, pos:Position):TypedExpr {
		final arrayAccess:TypedExpr = {
			expr: TArray(arrayLocal, indexLocal),
			pos: pos,
			t: valExpr.t
		};
		return {
			expr: TBinop(OpAssign, arrayAccess, valExpr),
			pos: pos,
			t: valExpr.t
		};
	}

	static function makeArrayPush(arrayLocal:TypedExpr, valExpr:TypedExpr, elemType:Type, pos:Position):TypedExpr {
		final arrayClassRef = switch (Context.getType("Array")) {
			case TInst(c, _): c;
			default: throw "Array type not found";
		};
		var pushField:Null<ClassField> = null;
		for (f in arrayClassRef.get().fields.get()) {
			if (f.name == "push") {
				pushField = f;
				break;
			}
		}
		final pushFieldExpr:TypedExpr = {
			expr: TField(arrayLocal, FInstance(arrayClassRef, [elemType], makeRef(pushField))),
			pos: pos,
			t: pushField.type
		};
		return {
			expr: TCall(pushFieldExpr, [valExpr]),
			pos: pos,
			t: Context.getType("Int")
		};
	}

	static function makeIntervalLoop(counterVar:TVar, boundVar:TVar, indexVar:TVar, bodyStmts:Array<TypedExpr>, pos:Position):TypedExpr {
		final boolType = Context.getType("Bool");
		final intType = Context.getType("Int");
		final voidType = Context.getType("Void");

		final cond:TypedExpr = {
			expr: TBinop(OpLt, makeLocal(counterVar, pos), makeLocal(boundVar, pos)),
			pos: pos,
			t: boolType
		};
		final inc:TypedExpr = {
			expr: TUnop(OpIncrement, true, makeLocal(counterVar, pos)),
			pos: pos,
			t: intType
		};
		final captureStmt:TypedExpr = {
			expr: TVar(indexVar, inc),
			pos: pos,
			t: voidType
		};

		final allBodyStmts = [captureStmt].concat(bodyStmts);
		return {
			expr: TWhile(cond, { expr: TBlock(allBodyStmts), pos: pos, t: voidType }, true),
			pos: pos,
			t: voidType
		};
	}

	static function getSortedMapClassRef():Ref<ClassType> {
		return switch (Context.getType("std.SortedMap")) {
			case TInst(c, _): c;
			default: throw "std.SortedMap not found";
		};
	}

	static function getSortedMapBuilderClassRef():Ref<ClassType> {
		final smRef = getSortedMapClassRef();
		for (f in smRef.get().statics.get()) {
			if (f.name == "builder") {
				switch (Context.follow(f.type)) {
					case TFun(_, ret):
						switch (Context.follow(ret)) {
							case TInst(bc, _): return bc;
							default:
						}
					default:
				}
			}
		}
		throw "SortedMap.builder return type not found";
	}

	static function makeSortedMapType(keyType:Type, valType:Type):Type {
		return TInst(getSortedMapClassRef(), [keyType, valType]);
	}

	static function makeSortedMapBuilderType(keyType:Type, valType:Type):Type {
		return TInst(getSortedMapBuilderClassRef(), [keyType, valType]);
	}

	static function makeSortedMapBuilderCall(keyType:Type, valType:Type, pos:Position):TypedExpr {
		final classRef = getSortedMapClassRef();
		var builderField:Null<ClassField> = null;
		for (f in classRef.get().statics.get()) {
			if (f.name == "builder") {
				builderField = f;
				break;
			}
		}
		final builderType = makeSortedMapBuilderType(keyType, valType);
		final fieldExpr:TypedExpr = {
			expr: TField({ expr: TTypeExpr(TClassDecl(classRef)), pos: pos, t: Context.getType("Void") }, FStatic(classRef, makeRef(builderField))),
			pos: pos,
			t: TFun([], builderType)
		};
		return {
			expr: TCall(fieldExpr, []),
			pos: pos,
			t: builderType
		};
	}

	static function makeSortedMapPutCall(builderLocal:TypedExpr, keyExpr:TypedExpr, valExpr:TypedExpr, pos:Position):TypedExpr {
		final builderClassRef = getSortedMapBuilderClassRef();
		var putField:Null<ClassField> = null;
		for (f in builderClassRef.get().fields.get()) {
			if (f.name == "put") {
				putField = f;
				break;
			}
		}
		final putFieldExpr:TypedExpr = {
			expr: TField(builderLocal, FInstance(builderClassRef, [keyExpr.t, valExpr.t], makeRef(putField))),
			pos: pos,
			t: putField.type
		};
		return {
			expr: TCall(putFieldExpr, [keyExpr, valExpr]),
			pos: pos,
			t: Context.getType("Void")
		};
	}

	static function makeSortedMapBuildCall(builderLocal:TypedExpr, sortedMapType:Type, pos:Position):TypedExpr {
		final builderClassRef = getSortedMapBuilderClassRef();
		var buildField:Null<ClassField> = null;
		for (f in builderClassRef.get().fields.get()) {
			if (f.name == "build") {
				buildField = f;
				break;
			}
		}
		final buildFieldExpr:TypedExpr = {
			expr: TField(builderLocal, FInstance(builderClassRef, [], makeRef(buildField))),
			pos: pos,
			t: TFun([], sortedMapType)
		};
		return {
			expr: TCall(buildFieldExpr, []),
			pos: pos,
			t: sortedMapType
		};
	}

	static function makeFieldRead(target:TypedExpr, fieldName:String, fieldType:Type, pos:Position):TypedExpr {
		final cf:ClassField = {
			name: fieldName,
			type: fieldType,
			pos: pos,
			doc: null,
			meta: null,
			kind: FVar(AccNormal, AccNormal),
			params: [],
			expr: null,
			isPublic: true,
			isFinal: true,
			isExtern: false,
			isAbstract: false,
			overloads: makeRef([])
		};
		return {
			expr: TField(target, FAnon(makeRef(cf))),
			pos: pos,
			t: fieldType
		};
	}

	static function replaceExprInPlace(target:TypedExpr, replacement:TypedExpr):Void {
		target.expr = replacement.expr;
		target.t = replacement.t;
		target.pos = replacement.pos;
	}
}

typedef PipelineCall = {
	kind:String,
	receiver:TypedExpr,
	lambdaExpr:TypedExpr,
	callExpr:TypedExpr,
	pos:Position
};
#end
