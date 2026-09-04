#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/** Shared typed checks for the small Std.isOfType lowering used by the samples. */
class TypeCheckHelper {
	public static function classOfType(type:Null<Type>):Null<ClassType> {
		if(type == null) {
			return null;
		}
		return switch(Context.follow(type)) {
			case TInst(ref, _): ref.get();
			case _: null;
		};
	}

	public static function classOfTypeExpr(expr:TypedExpr):Null<ClassType> {
		return switch(expr.expr) {
			case TTypeExpr(TClassDecl(ref)): ref.get();
			case TMeta(_, inner) | TParenthesis(inner) | TCast(inner, _): classOfTypeExpr(inner);
			case _: null;
		};
	}

	/** A non-null result means the value's static type decides the check. */
	public static function knownIsOfType(value:TypedExpr, target:ClassType):Null<Bool> {
		final actual = classOfType(value.t);
		if(actual == null || (actual.isInterface && !target.isInterface)) {
			return null;
		}
		return isSubtype(actual, target);
	}

	static function isSubtype(actual:ClassType, target:ClassType):Bool {
		if(actual.module == target.module && actual.name == target.name) {
			return true;
		}
		for(iface in actual.interfaces) {
			if(isSubtype(iface.t.get(), target)) {
				return true;
			}
		}
		return actual.superClass != null && isSubtype(actual.superClass.t.get(), target);
	}
}
#end
