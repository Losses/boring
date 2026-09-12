package boring;

#if swift_output
/**
    A counting method whose positional argument must bind the same way at
    its declaration and its call site.
**/
class RangeParameterOps {
    public static function gapCount(range:Int):Int
        return range + 1;

    public static function call():Int
        return gapCount(2);
}
#else
class RangeParameterOps {}
#end
