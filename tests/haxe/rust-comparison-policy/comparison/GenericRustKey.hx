package comparison;

import std.ReadOnlyArray;
import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

@:dataClass
class GenericSequenceKey<T> {
    public final values:ReadOnlyArray<T>;

    public function new(values:ReadOnlyArray<T>) {
        this.values = values;
    }
}

class GenericRustKey {
    public static function observe():String {
        final integers:SortedMapBuilder<GenericSequenceKey<Int>, String> = SortedMap.builder();
        integers.put(new GenericSequenceKey([1]), "B");
        integers.put(new GenericSequenceKey([-2]), "A");
        final integerTable = integers.build();

        final strings:SortedMapBuilder<GenericSequenceKey<String>, String> = SortedMap.builder();
        strings.put(new GenericSequenceKey(["\u{E000}"]), "B");
        strings.put(new GenericSequenceKey(["\u{10000}"]), "A");
        final stringTable = strings.build();

        return "signed=" + integerTable.valueAt(0) + integerTable.valueAt(1)
            + ";utf16=" + stringTable.valueAt(0) + stringTable.valueAt(1);
    }
}
