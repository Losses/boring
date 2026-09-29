package comparison;

import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

/**
    A generic key whose parameter takes no stored field. The plan has no
    direct comparison obligation for the parameter, so the comparator takes
    no trait bound for it, and instantiation at a record type does not raise
    the missing trait bound diagnostic. The struct carries the unused
    parameter as a zero-sized PhantomData marker, so the crate compiles
    end-to-end; the unused-param-key stage runs the builder at a record type
    and checks the stored field order.
**/
@:dataClass
class UnusedParamKey<T> {
    public final amount:Int;

    public function new(amount:Int) {
        this.amount = amount;
    }
}

class UnusedParamKeyProbe {
    public final tag:Int;

    public function new(tag:Int) {
        this.tag = tag;
    }
}

class UnusedParamKeyCase {
    public static function observe():String {
        final builder:SortedMapBuilder<UnusedParamKey<UnusedParamKeyProbe>, String> = SortedMap.builder();
        builder.put(new UnusedParamKey(2), "A");
        builder.put(new UnusedParamKey(10), "B");
        final table = builder.build();
        return "amount=" + table.valueAt(0) + table.valueAt(1);
    }
}
