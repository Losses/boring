package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import StructuralKeyValidator;
import PolicyQueries;


/**
    Type mapping from the translatable Haxe subset to Kotlin, per
    docs/specs/features/14-type-system-mapping.md and stdlib rulings.
    Cross-package types record their imports; the payload enum of the
    sealed error fold resolves to its exception class.
**/
class KotlinType {
    final imports:KotlinImports;
    final state:KotlinEmissionState;

    public function new(imports:KotlinImports, state:KotlinEmissionState) {
        this.imports = imports;
        this.state = state;
    }

    public function of(t:Null<Type>):String {
        if (t == null) {
            return "Unit";
        }
        return switch (t) {
            case TAbstract(a, params):
                final abs = a.get();
                if (ValueTypeSupport.isMarkedAbstract(abs)) {
                    imports.requireType(abs.module, abs.name);
                    abs.name;
                } else switch (pathOf(abs.pack, abs.name)) {
                    case "Int": "Int";
                    // The module precision switch selects the Float
                    // width for the whole compilation (feature spec 23).
                    case "Float": FloatPrecision.isF32() ? "Float" : "Double";
                    case "Bool": "Boolean";
                    case "Void": "Unit";
                    case "Null": of(params[0]) + "?";
                    case "haxe.ds.Map" if (params.length == 2): "MutableMap<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.ReadOnlyArray":
                        "List<" + of(params[0]) + ">";
                    case "haxe.Int64":
                        "Long";
                    case _: of(abs.type);
                }
            case TInst(c, params):
                final cls = c.get();
                switch (pathOf(cls.pack, cls.name)) {
                    case "String": "String";
                    case "std.StringBuf" | "StringBuf": "StringBuilder";
                    case "Array":
                        "MutableList<" + of(params[0]) + ">";
                    case "haxe.io.Bytes": "ByteArray";
                    case "haxe.io.BytesBuffer":
                        imports.requireType(cls.module, "BytesBuffer");
                        "BytesBuffer";
                    case "std.SortedMap":
                        imports.requireType(cls.module, "SortedMapTable");
                        "SortedMapTable<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.SortedMapBuilder":
                        imports.requireType(cls.module, "SortedMapTableBuilder");
                        "SortedMapTableBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.SortedSet":
                        imports.requireType(cls.module, "SortedSetTable");
                        "SortedSetTable<" + of(params[0]) + ">";
                    case "std.SortedSetBuilder":
                        imports.requireType(cls.module, "SortedSetTableBuilder");
                        "SortedSetTableBuilder<" + of(params[0]) + ">";
                    case _:
                        imports.requireType(cls.module, cls.name);
                        if (params.length > 0) {
                            cls.name + "<" + [for (p in params) of(p)].join(", ") + ">";
                        } else {
                            cls.name;
                        }
                }
            case TType(def, params):
                final d = def.get();
                if (d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
                    "ByteArray";
                } else if (d.pack.length == 0 && d.name == "Map" && params.length == 2) {
                    "MutableMap<" + of(params[0]) + ", " + of(params[1]) + ">";
                } else if (RuntimeResidents.isResident(d.module)) {
                    // Resident typedefs name function types for the
                    // TypeScript alias; Kotlin carries no named-alias
                    // requirement, so the reference lowers to the
                    // underlying function type with the arguments
                    // applied at the reference site.
                    of(haxe.macro.TypeTools.applyTypeParameters(d.type, d.params, params));
                } else if (params.length == 0) {
                    imports.requireType(d.module, d.name);
                    d.name;
                } else {
                    fail(t);
                }
            case TEnum(e, _):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                if (owner != null) {
                    owner;
                } else {
                    imports.requireType(en.module, en.name);
                    en.name;
                }
            case TFun(args, ret):
                "(" + [for (arg in args) of(arg.t)].join(", ") + ") -> " + of(ret);
            case TAnonymous(_):
                Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
                null;
            case TDynamic(_) | TMono(_):
                fail(t);
            case TLazy(f): of(f());
        }
    }

    function pathOf(pack:Array<String>, name:String):String {
        return PolicyQueries.pathOf(pack, name);
    }

    public static function classifyKey(t:Null<Type>, ?pos:haxe.macro.Expr.Position):KeyDomain {
        return PolicyQueries.classifyKey(t, pos);
    }

    static function validateDataClassField(cls:ClassType, field:ClassField):Void {
        PolicyQueries.validateDataClassField(cls, field, field.name);
    }

    public static function canEmitDataClassComparator(cls:ClassType):Bool {
        return PolicyQueries.canEmitDataClassComparator(cls);
    }

    static function isDataClassFieldKey(t:Type):Bool {
        return PolicyQueries.isDataClassFieldKey(t);
    }

    static function validateStructDef(def:DefType, pos:haxe.macro.Expr.Position, visited:Array<String>):Array<ClassField> {
        return StructuralKeyValidator.validateStructDef(def, pos, visited);
    }

    static function validateFieldType(t:Type, pos:haxe.macro.Expr.Position, visited:Array<String>):Void {
        StructuralKeyValidator.validateFieldType(t, pos, visited);
    }

    function fail(t:Type):String {
        Context.error("type has no Kotlin lowering in the translatable subset: " + Std.string(t), Context.currentPos());
        return null;
    }
}
#end
