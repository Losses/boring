package boring;

import std.SortedMap;
import std.SortedSet;

/** Key-range shape mirroring the TextRange key of the tiqian engine. */
@:dataClass
class RangeKey {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        this.start = start;
        this.end = end;
    }
}

/**
 * WidthIndependentAnnotationKey equivalent: a dataClass key carrying a
 * SortedMap<RangeKey, SortedSet<Int>> field, exactly the shape that drove the
 * hand-written keyEquals deep comparison before the comparison plan learned
 * SortedMap/SortedSet shapes (task perf/cmp-sorted-containers).
 */
@:dataClass
class SortedContainerKey {
    public final text:String;
    public final tiers:SortedMap<RangeKey, SortedSet<Int>>;

    public function new(text:String, tiers:SortedMap<RangeKey, SortedSet<Int>>) {
        this.text = text;
        this.tiers = tiers;
    }
}

class SortedContainerEq {
    public static function buildKey(text:String, seed:Int):SortedContainerKey {
        final tiers:SortedMapBuilder<RangeKey, SortedSet<Int>> = SortedMap.builder();
        final set:SortedSetBuilder<Int> = SortedSet.builder();
        set.put(seed);
        set.put(seed + 1);
        tiers.put(new RangeKey(0, seed), set.build());
        return new SortedContainerKey(text, tiers.build());
    }
}
