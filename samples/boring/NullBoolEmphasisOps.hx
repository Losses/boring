package boring;

import std.SortedMap;

/**
    Two more Null-boundary shapes: a coalescing ternary over a narrowed
    Null<Array> local read from a map (the guarded arm already holds the
    payload), and an object literal whose nullable field receives a
    non-null value.
*/
typedef NullBoolEmphasis = {
    public var clusterRangeStart:Null<Float>;
    public var anchorX:Float;
}

class NullBoolEmphasisOps {
    public static function emphasize(base:Float):NullBoolEmphasis {
        return { clusterRangeStart: base, anchorX: base * 2.0 };
    }

    public static function pickList(feats:Null<Array<String>>):Int {
        final list = feats != null ? feats : [];
        return list.length;
    }

    public static function lookupList(map:SortedMap<String, Array<String>>, key:String):Int {
        final feats = map.get(key);
        final list = feats != null ? feats : [];
        return list.length;
    }
}
