package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;

/**
	Tracks functions whose Array parameters are directly mutated in the function body,
	lowering them to `inout` in Swift declarations and adding `&` at call sites.
**/
class SwiftInoutParams {
	static final mutatingParamNames: Map<String, Map<String, Bool>> = [];
	static final mutatingParamIndices: Map<String, Map<Int, Bool>> = [];

	public static function key(module: String, className: String, fieldName: String): String {
		final mod = module != null && module != "" ? module : className;
		return mod + "::" + className + "." + fieldName;
	}

	public static function hasMutatingParams(module: String, className: String, fieldName: String): Bool {
		return mutatingParamNames.exists(key(module, className, fieldName));
	}

	public static function isMutatingParam(module: String, className: String, fieldName: String, paramName: String, paramIndex: Int = -1): Bool {
		final k = key(module, className, fieldName);
		final nameMap = mutatingParamNames.get(k);
		if(nameMap != null && nameMap.exists(paramName)) {
			return true;
		}
		if(paramIndex >= 0) {
			final indexMap = mutatingParamIndices.get(k);
			if(indexMap != null && indexMap.exists(paramIndex)) {
				return true;
			}
		}
		return false;
	}

	public static function isMutatingCallArg(fn: TypedExpr, argIndex: Int): Bool {
		return switch(stripWrap(fn).expr) {
			case TField(_, FInstance(c, _, cf)) | TField(_, FStatic(c, cf)):
				final cls = c.get();
				final fName = cf.get().name;
				final mod = cls.module != null && cls.module != "" ? cls.module : (cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name);
				final sigArgs = switch(Context.follow(fn.t)) {
					case TFun(args, _): args;
					case _: switch(Context.follow(cf.get().type)) {
						case TFun(args, _): args;
						case _: null;
					};
				};
				final paramName = (sigArgs != null && argIndex >= 0 && argIndex < sigArgs.length) ? sigArgs[argIndex].name : "";
				isMutatingParam(mod, cls.name, fName, paramName, argIndex);
			case _: false;
		};
	}

	public static function collect(mtypes: Array<ModuleType>): Void {
		for(k in mutatingParamNames.keys()) mutatingParamNames.remove(k);
		for(k in mutatingParamIndices.keys()) mutatingParamIndices.remove(k);

		for(mt in mtypes) {
			switch(mt) {
				case TClassDecl(c):
					final cls = c.get();
					final resident = RuntimeResidents.isResident(cls.module);
					if(cls.isExtern || (!resident && !inScope(cls.pos)) || (StringTools.endsWith(cls.name, "_Impl_") && ValueTypeSupport.markedAbstractOfClass(cls) == null)) {
						continue;
					}
					for(field in cls.statics.get()) {
						scanField(cls.module, cls.name, field);
					}
					for(field in cls.fields.get()) {
						scanField(cls.module, cls.name, field);
					}
					final ctor = cls.constructor;
					if(ctor != null) {
						scanField(cls.module, cls.name, ctor.get());
					}
				case _:
			}
		}
	}

	static function inScope(pos: haxe.macro.Expr.Position): Bool {
		final file = Context.getPosInfos(pos).file;
		for(root in Intercept.sourceRoots()) {
			final prefix = root.charAt(root.length - 1) == "/" ? root : root + "/";
			if(StringTools.startsWith(file, prefix)
				|| StringTools.startsWith(file, "./" + prefix)
				|| file.indexOf("/" + prefix) >= 0) {
				return true;
			}
		}
		return false;
	}

	static function isArrayType(t: Type): Bool {
		return switch(Context.follow(t)) {
			case TInst(c, _):
				final cls = c.get();
				final p = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
				p == "Array" || p == "haxe.ds.Array";
			case _: false;
		};
	}

	public static function stripWrap(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripWrap(inner);
			case _: e;
		};
	}

	static function scanField(module: String, className: String, field: ClassField): Void {
		switch(field.kind) {
			case FMethod(_):
				final e = field.expr();
				if(e == null) return;
				switch(e.expr) {
					case TFunction(tfunc):
						final arrayParams: Map<Int, {name: String, index: Int}> = [];
						for(i in 0...tfunc.args.length) {
							final arg = tfunc.args[i];
							if(isArrayType(arg.v.t)) {
								arrayParams.set(arg.v.id, {name: arg.v.name, index: i});
							}
						}
						var hasArrayParam = false;
						for(_ in arrayParams.keys()) {
							hasArrayParam = true;
							break;
						}
						if(!hasArrayParam) return;

						final mutatedNames: Map<String, Bool> = [];
						final mutatedIndices: Map<Int, Bool> = [];
						scanExprForMutations(tfunc.expr, arrayParams, mutatedNames, mutatedIndices);

						var hasMutated = false;
						for(_ in mutatedNames.keys()) {
							hasMutated = true;
							break;
						}
						if(hasMutated) {
							final k = key(module, className, field.name);
							mutatingParamNames.set(k, mutatedNames);
							mutatingParamIndices.set(k, mutatedIndices);
						}
					case _:
				}
			case _:
		}
	}

	static function scanExprForMutations(
		e: TypedExpr,
		arrayParams: Map<Int, {name: String, index: Int}>,
		mutatedNames: Map<String, Bool>,
		mutatedIndices: Map<Int, Bool>
	): Void {
		switch(e.expr) {
			case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
				switch(t.expr) {
					case TArray(arr, _):
						switch(stripWrap(arr).expr) {
							case TLocal(v) if(arrayParams.exists(v.id)):
								final info = arrayParams.get(v.id);
								mutatedNames.set(info.name, true);
								mutatedIndices.set(info.index, true);
							case _:
						}
					case _:
				}
			case TCall(fn, _):
				switch(stripWrap(fn).expr) {
					case TField(subj, FInstance(_, _, cf)):
						final n = cf.get().name;
						if(n == "push" || n == "set") {
							switch(stripWrap(subj).expr) {
								case TLocal(v) if(arrayParams.exists(v.id)):
									final info = arrayParams.get(v.id);
									mutatedNames.set(info.name, true);
									mutatedIndices.set(info.index, true);
								case _:
							}
						}
					case _:
				}
			case _:
		}
		TypedExprTools.iter(e, x -> scanExprForMutations(x, arrayParams, mutatedNames, mutatedIndices));
	}
}
#end
