package tests;

import boring.NullableArrayArgumentOps;
import std.Test;

class NullableArrayArgumentTests {
    @:test("a null-checked nullable array unwraps into a borrowed Array parameter")
    public static function checkedSum():Void {
        #if rust_output
        Test.equals(6, NullableArrayArgumentOps.checkedSum([1, 2, 3]));
        Test.equals(0, NullableArrayArgumentOps.checkedSum(null));
        #end
    }
}
