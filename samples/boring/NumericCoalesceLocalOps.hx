package boring;

#if rust_output
/**
    A local whose null-coalescing initializer materialized the inner value.
    Passing it to an Int parameter must not re-apply the null-to-zero
    bridge on the scalar the local holds.
*/
class NumericCoalesceLocalOps {
    public static function pick(?penalty:Null<Int>):Int {
        final cost = penalty == null ? 5 : penalty;
        return addOne(cost);
    }

    public static function sumPair(?left:Null<Int>, ?right:Null<Int>):Int {
        final a = left == null ? 1 : left;
        final b = right == null ? 2 : right;
        return combine(a, b);
    }

    static function addOne(value:Int):Int {
        return value + 1;
    }

    static function combine(a:Int, b:Int):Int {
        return a + b;
    }
}
#else
class NumericCoalesceLocalOps {}
#end
