package tests;

import std.Test;

#if swift_output
import boring.RangeParameterOps;
#end

class RangeParameterTests {
    @:test("a range-counting call passes its range positionally")
    public static function testCall():Void {
        #if swift_output
        Test.equals(3, RangeParameterOps.call());
        #else
        Test.equals(true, true);
        #end
    }
}
