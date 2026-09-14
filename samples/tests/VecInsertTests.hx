package tests;

import boring.VecInsertOps;
import std.Test;

class VecInsertTests {
    @:test("an Array insert widens the u32 position to the Vec usize index")
    public static function insertAt():Void {
        #if rust_output
        final values = VecInsertOps.insertAt(1, 9);
        Test.equals(4, values.length);
        Test.equals(1, values[0]);
        Test.equals(9, values[1]);
        Test.equals(2, values[2]);
        Test.equals(3, values[3]);
        Test.equals(7, VecInsertOps.firstAt(0, 7));
        #end
    }
}
