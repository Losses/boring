package boring;

#if swift_output
import std.SortedMap;

/**
    A sorted-map builder whose value type Haxe infers as `Null<Float>`.
    The runtime `get` already returns an optional, so the emitted table
    must keep the value parameter plain or `get` returns a double optional.
*/
class MapValueOptionalOps {
    public static function sum():Float {
        final b = SortedMap.builder();
        var i = 0;
        while (i < 3) {
            final prior = b.get(i);
            b.put(i, (prior == null ? 0.0 : prior) + 1.0);
            i += 1;
        }
        final m = b.build();
        var total = 0.0;
        i = 0;
        while (i < 3) {
            total += m.has(i) ? m.get(i) : 0.0;
            i += 1;
        }
        return total;
    }
}
#else
class MapValueOptionalOps {}
#end
