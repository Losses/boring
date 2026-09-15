package boring;

#if rust_output
/**
    An element loop whose subject is already a Rust reference. A function
    parameter, a local-function parameter, and a null-guard match binding all
    arrive as borrowed views, so the loop iterates the view without adding a
    second borrow.
*/
class BorrowedIterationSubjectOps {
    static function contains(values:Array<Int>, value:Int):Bool {
        for (candidate in values)
            if (candidate == value)
                return true;
        return false;
    }

    public static function unique(values:Array<Int>):Array<Int> {
        final out:Array<Int> = [];
        for (i in 0...values.length) {
            final s = values[i];
            if (!contains(out, s))
                out.push(s);
        }
        return out;
    }

    public static function uniqueNullable(values:Null<Array<Int>>):Array<Int> {
        final out:Array<Int> = [];
        if (values != null) {
            for (i in 0...values.length) {
                final s = values[i];
                if (!contains(out, s))
                    out.push(s);
            }
        }
        return out;
    }

    public static function uniqueThroughLocal(values:Array<Int>):Array<Int> {
        function inner(source:Array<Int>):Array<Int> {
            final out:Array<Int> = [];
            for (i in 0...source.length) {
                final s = source[i];
                if (!contains(out, s))
                    out.push(s);
            }
            return out;
        }
        return inner(values);
    }
}
#else
class BorrowedIterationSubjectOps {}
#end
