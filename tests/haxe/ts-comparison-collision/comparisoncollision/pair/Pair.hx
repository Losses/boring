package comparisoncollision.pair;

import std.SortedMap;

/**
    The file's own short name equals the nested record's short name from
    another module. The generated file declares class Pair and
    comparePair and must import the other module's Pair and comparePair
    under aliases; the generated comparator must call the imported one,
    not itself. The table read keys a sorted map on the imported record,
    so the sorted-key comparator resolution hits the same collision: its
    comparePair must bind to the imported declaration and never to the local
    one.
**/
@:dataClass
class Pair {
    public final inner:comparisoncollision.pair.other.Pair;

    public function new(inner:comparisoncollision.pair.other.Pair) {
        this.inner = inner;
    }

    public static function wrap(value:Int):Pair
        return new Pair(new comparisoncollision.pair.other.Pair(value));

    public static function tableRead():String {
        final b:SortedMapBuilder<comparisoncollision.pair.other.Pair, String> = SortedMap.builder();
        b.put(new comparisoncollision.pair.other.Pair(1), "one");
        b.put(new comparisoncollision.pair.other.Pair(2), "two");
        final m = b.build();
        return m.get(new comparisoncollision.pair.other.Pair(1)) + ";" + m.get(new comparisoncollision.pair.other.Pair(2));
    }
}
