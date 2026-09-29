package comparison;

import std.ReadOnlyArray;
import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

/**
    A generic key whose parameter is bound to a record type passes the
    source gates, so generation exits zero. The parameter trait supplies
    u32 and UString only, and the target compiler rejects the instantiation
    with the missing trait bound diagnostic E0277.
**/
@:dataClass
class RejectRecordParameterInner {
    public final amount:Int;

    public function new(amount:Int) {
        this.amount = amount;
    }
}

@:dataClass
class RejectRecordParameterKey<T> {
    public final values:ReadOnlyArray<T>;

    public function new(values:ReadOnlyArray<T>) {
        this.values = values;
    }
}

class RejectRecordParameter {
    public static function observe():String {
        final builder:SortedMapBuilder<RejectRecordParameterKey<RejectRecordParameterInner>, String> = SortedMap.builder();
        builder.build();
        return "unreached";
    }
}
