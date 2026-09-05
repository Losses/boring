#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;

/** Shared validation for structural sorted-table keys. */
class StructuralKeyValidator {
    public static function validateStructDef(def:DefType, pos:haxe.macro.Expr.Position, visited:Array<String>):Array<ClassField> {
        return switch (def.type) {
            case TAnonymous(anonRef):
                final fields = anonRef.get().fields.copy();
                fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
                for (f in fields) {
                    validateFieldType(f.type, f.pos, visited);
                }
                fields;
            case TType(innerDefRef, _):
                validateStructDef(innerDefRef.get(), pos, visited);
            case _:
                Context.error("sorted keyed tables support Int, String, structure, and dataClass keys in this implementation", pos);
                [];
        }
    }

    public static function validateFieldType(t:Type, pos:haxe.macro.Expr.Position, visited:Array<String>):Void {
        switch (t) {
            case TAbstract(a, _):
                final name = a.get().name;
                if (name == "Int" || name == "Bool") {
                    return;
                }
                Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
            case TInst(c, _):
                if (c.get().name == "String") {
                    return;
                }
                Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
            case TType(dRef, _):
                final def = dRef.get();
                if (visited.indexOf(def.name) >= 0) {
                    Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
                    return;
                }
                switch (def.type) {
                    case TAnonymous(_):
                        final nextVisited = visited.copy();
                        nextVisited.push(def.name);
                        validateStructDef(def, pos, nextVisited);
                    case TType(innerRef, _):
                        validateFieldType(def.type, pos, visited);
                    case _:
                        Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
                }
            case TLazy(f):
                validateFieldType(f(), pos, visited);
            case _:
                Context.error("structure key fields must be Int, Bool, String, or a nested structure", pos);
        }
    }
}
#end
