package boring;

#if swift_output
/**
    A counted `for i in 0...values.length` is rewritten as a Swift element
    loop. When the sequence is a guarded nullable, the element loop must
    unwrap it: Swift rejects iterating an optional.
*/
class ForInOptionalOps {
    public static function sum(values:Null<Array<Int>>):Int {
        if (values == null)
            return 0;
        var total = 0;
        for (i in 0...values.length) {
            final v = values[i];
            total += v;
        }
        return total;
    }

    public static function count(values:Null<Array<Int>>):Int {
        var total = 0;
        if (values != null)
            for (i in 0...values.length) {
                final v = values[i];
                total += 1;
            }
        return total;
    }

    public static function fallback(values:Null<Array<Int>>):Int {
        final vals = values == null ? [] : values;
        var total = 0;
        for (i in 0...vals.length) {
            final v = vals[i];
            total += v;
        }
        return total;
    }
}
#else
class ForInOptionalOps {}
#end
