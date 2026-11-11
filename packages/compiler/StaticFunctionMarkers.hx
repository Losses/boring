#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;

/** Shared declaration-side rules for features/10 static function markers. */
class StaticFunctionMarkers {
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
