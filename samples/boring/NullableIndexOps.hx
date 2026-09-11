package boring;

#if swift_output
/**
    An element read through an optional index: Swift's subscript needs a
    plain Int, so the nullable local unwraps at the index position.
*/
class NullableIndexOps {
    public static function at(values:Array<Int>, index:Null<Int>):Int {
        final i:Null<Int> = index;
        return values[i];
    }
}
#else
class NullableIndexOps {}
#end
