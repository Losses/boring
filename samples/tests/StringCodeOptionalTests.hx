package tests;

import std.Test;

#if swift_output
import boring.StringCodeOptionalOps;
#end

class StringCodeOptionalTests {
    @:test("optional string-code and parsed-array operands unwrap")
    public static function testOptionalOperands():Void {
        #if swift_output
        Test.equals("\\u0041", StringCodeOptionalOps.hexEscape("A", 0));
        Test.equals(0, StringCodeOptionalOps.parsedRoundTrip("7"));
        Test.equals(0, StringCodeOptionalOps.parsedRoundTrip("0"));
        #else
        Test.equals(true, true);
        #end
    }
}
