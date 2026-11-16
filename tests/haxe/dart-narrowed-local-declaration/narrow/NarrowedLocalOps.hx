package narrow;

/**
	Two locals whose values cannot be null at the declaration, so the Dart
	declaration must not carry a nullable type:

	- `edge` reads a local after a null guard;
	- `reference` reads a local the emitter already declared non-null
	  (the null-guard ternary of the same helper).

	Naming a nullable type here failed `dart analyze` when the value was
	passed to a `Float` parameter.
**/
class NarrowedLocalOps {
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
}
