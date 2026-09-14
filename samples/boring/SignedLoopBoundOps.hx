package boring;

#if rust_output
/**
    A range bound that carries the signed i32 domain. A Haxe Int loop bound
    can be negative, so the u32 range endpoint clamps the signed value; a
    negative bound yields an empty range. The named signedLoopBound rule
    covers the range endpoint position.
*/
class SignedLoopBoundOps {
    public static function fill(p:Int, e:Int):Int {
        var pointAfter = e + 1;
        if (pointAfter <= 0)
            return 0;
        var total = 0;
        var k = p;
        while (k < pointAfter) {
            total += 1;
            k += 1;
        }
        return total;
    }
}
#else
class SignedLoopBoundOps {}
#end
