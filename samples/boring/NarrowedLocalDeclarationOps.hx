package boring;

#if dart_output
/**
    Locals whose values cannot be null at the declaration: one reads a local
    after a null guard, one reads a null-guard ternary the emitter already
    declared non-null, and one passes the narrowed local to a non-null
    parameter. The samples exercised promoted reads in expressions, never in a
    local declaration, so Dart declared `double?` and the return and argument
    sites rejected it.
**/
class NarrowedLocalDeclarationOps {
    public static function guardedEdge(candidate:Null<Float>):Float {
        if (candidate == null)
            return 0.0;
        final edge = candidate;
        return edge;
    }

    public static function stretched(referenceValue:Null<Float>):Float {
        final stretch = referenceValue == null ? Math.POSITIVE_INFINITY : referenceValue;
        final reference = stretch;
        return reference;
    }

    public static function passedToParameter(candidate:Null<Float>):Float {
        if (candidate == null)
            return -1.0;
        final edge = candidate;
        return roundTrip(edge);
    }

    static function roundTrip(value:Float):Float
        return value;
}
#else
class NarrowedLocalDeclarationOps {}
#end
