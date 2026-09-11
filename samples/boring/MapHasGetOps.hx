package boring;

import std.SortedMap;

#if swift_output
/**
    The guarded lookup idiom. `map.has(k) ? map.get(k) : fallback` proves the
    value is present, but the Swift `get` call stays optional and the ternary
    is rejected in a non-optional context. The emitter lowers the guarded
    lookup to nil coalescing.
*/
class MapHasGetOps {
    public static function valueOr(m:SortedMap<Int, Float>, key:Int, fallback:Float):Float {
        return m.has(key) ? m.get(key) : fallback;
    }

    public static function sum(keys:Array<Int>, values:SortedMap<Int, Int>):Int {
        var total = 0;
        for (k in keys) {
            total += values.has(k) ? values.get(k) : 0;
        }
        return total;
    }

    public static function nested(rows:SortedMap<String, SortedMap<Int, Float>>, row:String, key:Int):Float {
        final inner = rows.get(row);
        return inner == null ? 0.0 : (inner.has(key) ? inner.get(key) : 0.0);
    }
}
#else
class MapHasGetOps {}
#end
