package dartcomparison;

import boring.PrintedEnumOps.PrintedMark;
import comparison.ParameterCompositionCases.ComparedParameterKey;
import std.SortedMap;
import std.SortedMap.SortedMapBuilder;

typedef MarkAlias = PrintedMark;
enum NativeOrder { Zebra; Alpha; }

@:dataClass
class NativeKey {
    public final value:NativeOrder;
    public function new(value:NativeOrder) this.value = value;
}

@:dataClass
class AliasKey {
    public final value:PrintedMark;
    public function new(value:PrintedMark) this.value = value;
}

class EnumCases {
    public static function nativeValue():SortedMapBuilder<ComparedParameterKey<NativeOrder>, String> return SortedMap.builder();
    /** Payload-enum fields are rejected at the key-type gate since spec 16
        kind 3 was narrowed to payload-free enums, so this record key stays
        payload-free; payload-enum comparators are exercised through the
        AliasKey resident comparator the native program calls. */
    public static function observe():String {
        final nativeTable = nativeValue();
        nativeTable.put(new ComparedParameterKey(NativeOrder.Alpha), "A");
        nativeTable.put(new ComparedParameterKey(NativeOrder.Zebra), "Z");
        final natives = nativeTable.build();
        return natives.valueAt(0) + natives.valueAt(1);
    }
}
