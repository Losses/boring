package comparison;

#if swift_output
import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

@:dataClass
private class SameKey {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}

class LeftSameKeyCase {
    public static function observe():String {
        final builder:SortedMapBuilder<SameKey, String> = SortedMap.builder();
        builder.put(new SameKey(2), "B");
        builder.put(new SameKey(1), "A");
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1);
    }
}
#end
