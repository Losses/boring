package boring;

#if (rust_output || kotlin_output)
typedef NullTagRecord = {
    final label:String;
    final detail:Null<String>;
    final weight:Null<Float>;
};

/**
    An object literal whose field expressions carry one more Null wrapper
    than the typedef fields they unify with: a ternary whose Null-typed arm
    is joined with null is Null<Null<T>>, and Haxe keeps that inflated type
    on the anonymous structure while still accepting the literal against the
    typedef. The printed signature of the inflated structure differs from
    the registered typedef signature, so nominal lowering must fall back to
    unification-based matching when the exact-signature lookup misses.
*/
class NullInflatedLiteralOps {
    static final labels:Array<String> = ["known"];
    static final details:Array<Null<String>> = ["d", null];
    static final weights:Array<Null<Float>> = [1.0, null];

    static function index(label:String):Int {
        for (i in 0...labels.length)
            if (labels[i] == label)
                return i;
        return 1;
    }

    public static function has(label:String):Bool {
        return index(label) == 0;
    }

    public static function record(label:String):NullTagRecord {
        final pick = index(label);
        final detail = has(label) ? details[pick] : null;
        final weight = has(label) ? weights[pick] : null;
        return {
            label: label,
            detail: detail,
            weight: weight,
        };
    }
}
#else
class NullInflatedLiteralOps {}
#end
