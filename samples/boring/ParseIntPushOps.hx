package boring;

#if rust_output
/**
    A Std.parseInt result pushed into a business u32 array. The parse lowers to
    an i32 Option, so the pushed element unwraps and reinterprets its bits. The
    named parseIntPush rule covers the direct and local positions.
*/
class ParseIntPushOps {
    public static function parseAll(values:Array<String>):Array<Int> {
        final out:Array<Int> = [];
        for (value in values) {
            out.push(Std.parseInt(value));
        }
        return out;
    }

    public static function parseLocal(values:Array<String>):Array<Int> {
        final out:Array<Int> = [];
        for (value in values) {
            final parsed = Std.parseInt(value);
            out.push(parsed);
        }
        return out;
    }
}
#else
class ParseIntPushOps {}
#end
