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
}

/**
 * Default argument expansion pass per docs/specs/features/22-default-argument-expansion.md.
 * Completes omitted trailing arguments at typed call sites with compile-time constants.
 */
class DefaultArgExpander {
	static final fieldDefaults:Map<String, Array<Null<DefaultArgValue>>> = new Map();
	static final fieldDefaultsByName:Map<String, Array<Null<DefaultArgValue>>> = new Map();

	static final localDefaults:Map<String, Array<Null<DefaultArgValue>>> = new Map();
	static final localDefaultsByName:Map<String, Array<Null<DefaultArgValue>>> = new Map();

	public static function registerClassFields(classType:ClassType, fields:Array<Field>):Void {
		final classKey = getClassKey(classType);
		for (index in 0...fields.length) {
			final field = fields[index];
			switch (field.kind) {
				case FieldType.FFun(fun):
					final defaults:Array<Null<DefaultArgValue>> = [];
					var hasDefault = false;
					for (argIdx in 0...fun.args.length) {
						final arg = fun.args[argIdx];
						if (arg.value != null) {
							final v = evalConstantExpr(arg.value, classType);
							defaults.push(v);
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
					}
					if (fun.expr != null) {
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
		final defaults:Array<Null<DefaultArgValue>> = [];
		var hasDefault = false;
		for (argIdx in 0...func.args.length) {
			final arg = func.args[argIdx];
			if (arg.value != null) {
				final v = evalConstantExpr(arg.value, classType);
				defaults.push(v);
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
		}
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

	public static function completeRootExpr(root:TypedExpr):Void {
		if (root == null) return;
		completeExpr(root);
	}

	static function completeExpr(e:TypedExpr):Void {
		if (e == null) return;
		switch (e.expr) {
			case TypedExprDef.TFunction(f):
				completeExpr(f.expr);
			default:
				haxe.macro.TypedExprTools.iter(e, completeExpr);
		}
		switch (e.expr) {
			case TypedExprDef.TCall(callee, args):
				completeCall(e, callee, args);
			case TypedExprDef.TNew(c, _, args):
				completeNew(e, c.get(), args);
			default:
		}
	}

	static function completeCall(callExpr:TypedExpr, callee:TypedExpr, args:Array<TypedExpr>):Void {
		if (callee == null) return;
		final followed = Context.follow(callee.t);
		final params:Array<{name:String, opt:Bool, t:Type}> = switch (followed) {
			case Type.TFun(argsList, _): argsList;
			default: return;
		};
		if (args.length >= params.length) {
			return;
		}

		final defaults = findDefaultsForCallee(callee);

		for (i in args.length...params.length) {
			final param = params[i];
			final defVal:Null<DefaultArgValue> = (defaults != null && i < defaults.length) ? defaults[i] : null;

			if (defVal != null) {
				args.push(makeTypedConst(defVal, param.t, callExpr.pos));
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

	static function findDefaultsForCallee(callee:TypedExpr):Null<Array<Null<DefaultArgValue>>> {
		final unwrapped = stripWrap(callee);
		switch (unwrapped.expr) {
			case TypedExprDef.TField(receiver, fa):
				return findDefaultsForFieldAccess(receiver, fa);
			case TypedExprDef.TLocal(v):
				if (localDefaultsByName.exists(v.name)) {
					return localDefaultsByName.get(v.name);
				}
				return null;
			default:
				return null;
		}
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
		if (fieldDefaultsByName.exists(fieldName)) {
			return fieldDefaultsByName.get(fieldName);
		}
		return null;
	}

	static function completeNew(newExpr:TypedExpr, cls:ClassType, args:Array<TypedExpr>):Void {
		final defaults = lookupFieldDefaults(cls, "new");
		if (defaults == null) return;

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

		for (i in args.length...params.length) {
			final param = params[i];
			final defVal:Null<DefaultArgValue> = (i < defaults.length) ? defaults[i] : null;
			if (defVal != null) {
				args.push(makeTypedConst(defVal, param.t, newExpr.pos));
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
		};
	}
}
#end
