package tests;

import std.Test;

#if swift_output
import boring.MutableBufFieldOps;
import boring.MutableBufFieldOps.ArrayInsertOps;
#end

class MutableBufFieldTests {
    @:test("a final StringBuf field mutates and Array.insert names its position")
    public static function testField():Void {
        #if swift_output
        final ops = new MutableBufFieldOps();
        ops.append("a");
        ops.append("b");
        Test.equals(4, ops.length());

        Test.equals("1,2,3", ArrayInsertOps.insertAt([1, 3], 1, 2));
        #else
        Test.equals(true, true);
        #end
    }
}
