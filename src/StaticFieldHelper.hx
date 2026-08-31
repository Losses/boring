#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/**
	Shared rules for feature 30 static field declarations.

	Static initializers deliberately stay a small, target-independent
	language.  The target emitters call `validatedInitializer` before
	raversing an initializer, so an unsupported expression cannot turn into
	a target-specific partial declaration.
**/
class StaticFieldHelper {
	public static inline final INVALID_INITIALIZER = "static field initializers accept null, literal, and empty array forms only";

	public static function initializer(field: ClassField): Null<TypedExpr> {
		if(field == null || field.expr == null) {
			return null;
		}
		return field.expr();
	}

	public static function validatedInitializer(field: ClassField): Null<TypedExpr> {
		final init = initializer(field);
		if(init == null || !isSanctioned(init)) {
			Context.error(INVALID_INITIALIZER, field.pos);
			return null;
		}
		return init;
	}

	public static function isSanctioned(e: TypedExpr): Bool {
		return switch(stripDecorations(e).expr) {
			case TConst(TNull): true;
			case TConst(TBool(_)): true;
			case TConst(TInt(_)): true;
			case TConst(TFloat(_)): true;
			case TConst(TString(_)): true;
			case TArrayDecl(elements): elements.length == 0;
			case _: false;
		};
	}

	public static function isConstValue(field: ClassField): Bool {
		if(field == null || !field.isFinal || !isScalarOrString(field.type)) {
			return false;
		}
		final init = initializer(field);
		if(init == null) {
			return false;
		}
		return switch(stripDecorations(init).expr) {
			case TConst(TBool(_)): true;
			case TConst(TInt(_)): true;
			case TConst(TFloat(_)): true;
			case TConst(TString(_)): true;
			case _: false;
		};
	}

	public static function isArrayType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TInst(c, _): c.get().name == "Array";
			case _: false;
		};
	}

	public static function isNullableType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TAbstract(a, _): a.get().name == "Null";
			case _: false;
		};
	}

	public static function isStringType(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TInst(c, _): c.get().name == "String";
			case _: false;
		};
	}

	public static function isScalarOrString(t: Null<Type>): Bool {
		if(t == null) {
			return false;
		}
		return switch(Context.follow(t)) {
			case TAbstract(a, _):
				switch(a.get().name) {
					case "Int" | "Float" | "Bool": true;
					case _: false;
				}
			case TInst(c, _): c.get().name == "String";
			case _: false;
		};
	}

	public static function stripDecorations(e: TypedExpr): TypedExpr {
		return switch(e.expr) {
			case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripDecorations(inner);
			case _: e;
		};
	}
}
#end
