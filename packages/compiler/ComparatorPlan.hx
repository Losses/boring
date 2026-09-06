#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
    Shared field classification for the per-target dataClassComparator
    printers. `entries` filters the comparable fields of a `:dataClass`
    exactly as the five Decl copies did and peels the nullable and
    ReadOnlyArray layers once. The two strictness flags reproduce each
    target's own ReadOnlyArray detection at the outer arm and the inner
    peel; the printers keep every emitted string.
**/
class ComparatorPlan {
    public static function entries(cls:ClassType, outerStrict:Bool, innerStrict:Bool):Array<ComparatorEntry> {
        final result:Array<ComparatorEntry> = [];
        for (x in cls.fields.get()) {
            final comparable = switch (x.kind) {
                case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                case _: false;
            };
            if (comparable)
                result.push({field: x, kind: classify(x.type, outerStrict, innerStrict)});
        }
        return result;
    }

    static function classify(t:Type, outerStrict:Bool, innerStrict:Bool):ComparatorFieldKind {
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                switch (readOnlyArrayElement(params[0], innerStrict)) {
                    case null: NullableScalar(params[0]);
                    case element: NullableArray(element);
                }
            case TAbstract(a, params) if (readOnlyArrayMatch(a.get(), outerStrict) && params.length == 1):
                ReadOnlyArrayField(params[0]);
            case _: PlainField;
        };
    }

    static function readOnlyArrayMatch(a:AbstractType, strict:Bool):Bool {
        return a.name == "ReadOnlyArray" && (!strict || a.pack.join(".") == "std");
    }

    static function readOnlyArrayElement(t:Type, strict:Bool):Null<Type> {
        return switch (t) {
            case TAbstract(a, params) if (readOnlyArrayMatch(a.get(), strict) && params.length == 1): params[0];
            case TLazy(f): readOnlyArrayElement(f(), strict);
            case _: null;
        };
    }
}

enum ComparatorFieldKind {
    NullableScalar(inner:Type);
    NullableArray(element:Type);
    ReadOnlyArrayField(element:Type);
    PlainField;
}

typedef ComparatorEntry = {
    final field:ClassField;
    final kind:ComparatorFieldKind;
}
#end
