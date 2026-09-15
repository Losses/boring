package boring;

#if rust_output
/**
    Haxe Array.splice(pos, len) removes len elements at pos and returns the
    removed sub-array. The vecSpliceDrain heuristic lowers it through
    Vec::drain on a usize range so the range bound types match the Vec
    index domain instead of the Haxe u32 Int domain.
*/
class VecSpliceOps {
    /** Remove one element from the middle and discard the return value. */
    public static function removeSingle():Array<Int> {
        final out = [1, 2, 3];
        out.splice(1, 1);
        return out;
    }

    /** Remove one element and capture the removed sub-array. */
    public static function captureRemoved():Array<Int> {
        final out = [10, 20, 30, 40];
        final removed = out.splice(2, 1);
        return removed;
    }

    /** Remove multiple elements from the start. */
    public static function removeHead(count:Int):Array<Int> {
        final out = [1, 2, 3, 4, 5];
        out.splice(0, count);
        return out;
    }
}
#else
class VecSpliceOps {}
#end