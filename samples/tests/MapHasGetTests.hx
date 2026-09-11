package tests;

import std.Test;
import std.SortedMap;

#if swift_output
import boring.MapHasGetOps;
#end

class MapHasGetTests {
    @:test("a guarded map lookup lowers to nil coalescing")
    public static function testGuardedLookup():Void {
        #if swift_output
        final floatBuilder:SortedMapBuilder<Int, Float> = SortedMap.builder();
        floatBuilder.put(2, 1.5);
        final floats = floatBuilder.build();
        Test.equals(true, MapHasGetOps.valueOr(floats, 2, 9.0) == 1.5);
        Test.equals(true, MapHasGetOps.valueOr(floats, 3, 9.0) == 9.0);

        final intBuilder:SortedMapBuilder<Int, Int> = SortedMap.builder();
        intBuilder.put(5, 7);
        Test.equals(7, MapHasGetOps.sum([5, 6], intBuilder.build()));

        final rowsBuilder:SortedMapBuilder<String, SortedMap<Int, Float>> = SortedMap.builder();
        rowsBuilder.put("a", floats);
        final rows = rowsBuilder.build();
        Test.equals(true, MapHasGetOps.nested(rows, "a", 2) == 1.5);
        Test.equals(true, MapHasGetOps.nested(rows, "a", 3) == 0.0);
        #else
        Test.equals(true, true);
        #end
    }
}
