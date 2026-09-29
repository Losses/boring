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
    public static function payload():SortedMapBuilder<ComparedParameterKey<PrintedMark>, String> return SortedMap.builder();
    public static function nativeValue():SortedMapBuilder<ComparedParameterKey<NativeOrder>, String> return SortedMap.builder();
    public static function observe():String {
        final table = payload();
        table.put(new ComparedParameterKey(PrintedMark.Tag("x", 1)), "T");
        table.put(new ComparedParameterKey(PrintedMark.Plain), "P");
        table.put(new ComparedParameterKey(PrintedMark.Ring(9)), "R");
        final values = table.build();
        final nativeTable = nativeValue();
        nativeTable.put(new ComparedParameterKey(NativeOrder.Alpha), "A");
        nativeTable.put(new ComparedParameterKey(NativeOrder.Zebra), "Z");
        final natives = nativeTable.build();
        return values.valueAt(0) + values.valueAt(1) + values.valueAt(2) + ";" + natives.valueAt(0) + natives.valueAt(1);
    }
}
