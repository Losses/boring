package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import StructuralKeyValidator;
import PolicyQueries;

/**
    Type mapping from the translatable Haxe subset to TypeScript, per
    docs/specs/features/14-type-system-mapping.md and the stdlib rulings:
    haxe.io.Bytes is Uint8Array (stdlib/01), haxe.io.BytesBuffer is the
    runtime growth class (stdlib/02), haxe.Int64 stays out of value
    domain (stdlib/05), ReadOnlyArray<T> is `readonly T[]` (features/18).
**/
class TsType {
    final imports:TsImports;

    public function new(imports:TsImports) {
        this.imports = imports;
    }

    public function of(t:Null<Type>):String {
        if (t == null) {
            return "void";
        }
        return switch (t) {
            case TAbstract(a, params):
                final abs = a.get();
                if (ValueTypeSupport.isMarkedAbstract(abs)) {
                    imports.type(abs.module, abs.name);
                    abs.name;
                } else switch (pathOf(abs.pack, abs.name)) {
                    case "Int", "Float": "number";
                    case "Bool": "boolean";
                    case "Void": "void";
                    case "Null": of(params[0]) + " | null";
                    case "haxe.ds.Map" if (params.length == 2): "Map<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.ReadOnlyArray": "readonly " + arrayElement(params[0]) + "[]";
                    case "haxe.Int64": "bigint";
                    case _: of(abs.type);
                };
            case TInst(c, params):
                final cls = c.get();
                switch (pathOf(cls.pack, cls.name)) {
                    case "String" | "std.StringBuf" | "StringBuf": "string";
                    case "Array": arrayElement(params[0]) + "[]";
                    case "haxe.Exception": "Error";
                    case "haxe.io.Bytes": "Uint8Array";
                    case "haxe.io.BytesBuffer":
                        imports.runtime("BytesBuffer");
                        "BytesBuffer";
                    case "std.SortedMap":
                        imports.runtime("SortedMapTable");
                        "SortedMapTable<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.SortedMapBuilder":
                        imports.runtime("SortedMapTableBuilder");
                        "SortedMapTableBuilder<" + of(params[0]) + ", " + of(params[1]) + ">";
                    case "std.SortedSet":
                        imports.runtime("SortedSetTable");
                        "SortedSetTable<" + of(params[0]) + ">";
                    case "std.SortedSetBuilder":
                        imports.runtime("SortedSetTableBuilder");
                        "SortedSetTableBuilder<" + of(params[0]) + ">";
                    case _:
                        imports.type(cls.module, cls.name);
                        if (params.length > 0) {
                            cls.name + "<" + [for (p in params) of(p)].join(", ") + ">";
                        } else {
                            cls.name;
                        }
                }
            case TType(def, params):
                final d = def.get();
                if (d.pack.join(".") == "haxe.io" && d.name == "Bytes") {
                    "Uint8Array";
                } else if (d.pack.length == 0 && d.name == "Map" && params.length == 2) {
                    "Map<" + of(params[0]) + ", " + of(params[1]) + ">";
                } else if (RuntimeResidents.isResident(d.module) && params.length > 0) {
                    // A resident typedef lowers to a generic type alias
                    // inside the runtime file (TsDecl.functionTypeDecl);
                    // references carry the applied arguments.
                    d.name + "<" + [for (p in params) of(p)].join(", ") + ">";
                } else if (params.length == 0) {
                    imports.type(d.module, d.name);
                    d.name;
                } else {
                    fail(t);
                }
            case TEnum(e, _):
                final en = e.get();
                imports.type(en.module, en.name);
                en.name;
            case TFun(args, ret):
                // Function types written without argument names, like the
                // comparator `(K, K) -> Int`, still need positional names
                // in TypeScript.
                "(" + [
                    for (index in 0...args.length) {
                        final arg = args[index];
                        final argName = arg.name != "" ? arg.name : "a" + index;
                        '${argName}: ${of(arg.t)}';
                    }
                ].join(", ") + ") => " + of(ret);
            case TAnonymous(_):
                Context.error("anonymous structure types must be named typedefs before translation", Context.currentPos());
                null;
            case TDynamic(_) | TMono(_):
                fail(t);
            case TLazy(f): of(f());
        }
    }

    public function moduleBase(module:String):String {
        final parts = module.split(".");
        return parts[parts.length - 1];
    }

    /**
        An array element that is itself a nullable type renders wrapped
        in parentheses: `of` spells Null<T> as a top-level union and the
        postfix `[]` would otherwise bind to the null side alone.
    **/
    function arrayElement(elem:Type):String {
        return switch (elem) {
            case TAbstract(a, _) if (pathOf(a.get().pack, a.get().name) == "Null"): "(" + of(elem) + ")";
            case _: of(elem);
        }
    }

    function pathOf(pack:Array<String>, name:String):String {
        return PolicyQueries.pathOf(pack, name);
    }

    public static function classifyKey(t:Null<Type>, ?pos:haxe.macro.Expr.Position):KeyDomain {
        return PolicyQueries.classifyKey(t, pos);
    }

    static function validateStructDef(def:DefType, pos:haxe.macro.Expr.Position, visited:Array<String>):Array<ClassField> {
        return StructuralKeyValidator.validateStructDef(def, pos, visited);
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

    static function validateFieldType(t:Type, pos:haxe.macro.Expr.Position, visited:Array<String>):Void {
        StructuralKeyValidator.validateFieldType(t, pos, visited);
    }

    function fail(t:Type):String {
        Context.error("type has no TypeScript lowering in the translatable subset: " + Std.string(t), Context.currentPos());
        return null;
    }
}
#end
