package tests;

import std.Test;
import std.SortedMap;

#if swift_output
import boring.OptionalValueUseOps;
import boring.OptionalValueUseMetrics;
import boring.OptionalValueUseHolder;
#end

class OptionalValueUseTests {
    @:test("a nullable value unwraps at the remaining value uses")
    public static function testValueUses():Void {
        #if swift_output
        Test.equals(5, OptionalValueUseOps.tagValue(5));
        Test.equals(0, OptionalValueUseOps.tagValue(null));

        Test.equals(true, OptionalValueUseOps.enabled(true));
        Test.equals(true, OptionalValueUseOps.enabled(null));
        Test.equals(false, OptionalValueUseOps.enabled(false));

        final builder:SortedMapBuilder<Int, Float> = SortedMap.builder();
        builder.put(2, 1.5);
        final floats = builder.build();
        Test.equals(true, OptionalValueUseOps.lookup(floats, 2) == 1.5);
        Test.equals(true, OptionalValueUseOps.lookup(floats, 3) == 0.0);

        Test.equals(true, OptionalValueUseOps.metrics(new OptionalValueUseMetrics(2.0), 1.0));
        Test.equals(false, OptionalValueUseOps.metrics(new OptionalValueUseMetrics(null), 1.0));

        Test.equals(true, OptionalValueUseOps.negate(2.5) == -2.5);
        Test.equals(true, OptionalValueUseOps.negate(null) == 0.0);

        final values = [1.0, 2.0];
        OptionalValueUseOps.accumulate(values, 3.0);
        Test.equals(true, values[0] == 4.0);
        OptionalValueUseOps.accumulate(values, null);
        Test.equals(true, values[0] == 4.0);

        Test.equals("a-b.", OptionalValueUseOps.describe("a", "b"));
        Test.equals("a-.", OptionalValueUseOps.describe("a", null));

        final holder = new OptionalValueUseHolder(9);
        Test.equals(9, OptionalValueUseOps.found(true, holder).value);
        #else
        Test.equals(true, true);
        #end
    }
}
