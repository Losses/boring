package boring;

#if swift_output
/**
    `Array.join` on a non-string element array: Swift's
    `joined(separator:)` is String-only, so each value maps through its
    Haxe string form before the join.
*/
class ArrayJoinOps {
    public static function joinInts(values:Array<Int>):String
        return values.join(", ");

    public static function joinFloats(values:Array<Float>):String
        return values.join(", ");
}
#else
class ArrayJoinOps {}
#end
