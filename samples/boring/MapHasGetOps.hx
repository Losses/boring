package boring;

import std.SortedMap;

#if swift_output
class MapHasGetBudget {
    public final leadingNatural:Float;

    public function new(leadingNatural:Float) {
        this.leadingNatural = leadingNatural;
    }
}

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

    /** `has ? get : null` must stay a single optional for the later guard. */
    public static function budget(m:SortedMap<Int, MapHasGetBudget>, key:Int):Float {
        final previousBudget = m.has(key) ? m.get(key) : null;
        return previousBudget == null ? 0 : previousBudget.leadingNatural;
    }

    public static function sampleBudget():SortedMap<Int, MapHasGetBudget> {
        final b:SortedMapBuilder<Int, MapHasGetBudget> = SortedMap.builder();
        b.put(4, new MapHasGetBudget(3.25));
        return b.build();
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
