package tests;

import std.Test;

#if rust_output
import boring.NullableStringViewOps;
#end

class NullableStringViewOpsTests {
    @:test("a nullable String argument unwraps at a str parameter")
    public static function testNullableView():Void {
        #if rust_output
        Test.equals(0, NullableStringViewOps.lengthOrZero(null));
        Test.equals(3, NullableStringViewOps.lengthOrZero("abc"));
        #end
        Test.equals(true, true);
    }
}
