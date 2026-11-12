#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;

/** Shared declaration-side rules for features/10 static function markers. */
class StaticFunctionMarkers {
    /** The variable form has no receiver and no mutable spelling. */
    public static final FIELD_MARKER_ERROR = "top-level markers on fields accept static final constants only";

    public static function isTopLevel(field:ClassField):Bool {
        SharedModuleTrace.record("StaticFunctionMarkers");
        return field.meta.has(":topLevel");
    }

    public static function isExtension(field:ClassField):Bool {
        SharedModuleTrace.record("StaticFunctionMarkers");
        return field.meta.has(":extension");
    }

    public static function isMarked(field:ClassField):Bool {
        SharedModuleTrace.record("StaticFunctionMarkers");
        return isTopLevel(field) || isExtension(field);
    }

    public static function validate(f:ClassFuncData):Void {
        SharedModuleTrace.record("StaticFunctionMarkers");
        if (!isMarked(f.field)) {
            return;
        }
        if (!f.isStatic || (isExtension(f.field) && (f.args.length == 0 || isTypeParameter(f.args[0].type)))) {
            Context.error("top-level markers accept static functions with a concrete receiver only", f.field.pos);
        }
        if (isTopLevel(f.field) && isExtension(f.field)) {
            Context.error("top-level markers accept static functions with a concrete receiver only", f.field.pos);
        }
    }

    public static function validateAll(funcFields:Array<ClassFuncData>):Void {
        SharedModuleTrace.record("StaticFunctionMarkers");
        for (f in funcFields) {
            validate(f);
        }
    }

    /**
        The variable form of `@:topLevel` (features/10 field form): a
        `static final` constant whose declaration leaves its holder's
        namespace and emits at file top level. It is the same metadata the
        function form reads, so a reference site needs no second spelling;
        the declaration-side rules below decide which variables may carry
        it.
    **/
    public static function isTopLevelField(field:ClassField):Bool {
        SharedModuleTrace.record("StaticFunctionMarkers");
        return field.meta.has(":topLevel");
    }

    /**
        Declaration-side rules for the variable form. A variable has no
        receiver, so `@:extension` has no meaning here and is rejected;
        and the top-level form is the constant form only, so an instance or
        mutable field is rejected too. An unmarked field keeps its
        namespace shape.
    **/
    public static function validateField(field:ClassField, isStatic:Bool):Void {
        SharedModuleTrace.record("StaticFunctionMarkers");
        if (!isTopLevelField(field)) {
            if (isExtension(field)) {
                Context.error(FIELD_MARKER_ERROR, field.pos);
            }
            return;
        }
        if (isExtension(field) || !isStatic || !field.isFinal) {
            Context.error(FIELD_MARKER_ERROR, field.pos);
        }
    }

    public static function validateAllVars(varFields:Array<ClassVarData>):Void {
        SharedModuleTrace.record("StaticFunctionMarkers");
        for (v in varFields) {
            validateField(v.field, v.isStatic);
        }
    }

    public static function isTypeParameter(t:Null<Type>):Bool {
        SharedModuleTrace.record("StaticFunctionMarkers");
        if (t == null) {
            return false;
        }
        switch (t) {
            case TAbstract(a, _) if (a.get().name == "Null"):
                return false;
            case _:
        }
        return switch (Context.follow(t)) {
            case TInst(c, _):
                switch (c.get().kind) {
                    case KTypeParameter(_): true;
                    case _: false;
                }
            case _: false;
        };
    }
}
#end
