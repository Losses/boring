package tests;

import std.Test;

#if swift_output
import boring.CtorOptArgOps;
#end

class CtorOptArgTests {
    @:test("a nullable value unwraps at a value-typed constructor argument")
    public static function testConstructorArg():Void {
        #if swift_output
        Test.equals(5, CtorOptArgOps.coalesced(5));
        Test.equals(0, CtorOptArgOps.coalesced(null));
        Test.equals(-1, CtorOptArgOps.guarded(null));
        Test.equals(9, CtorOptArgOps.guarded(9));
        #else
        Test.equals(true, true);
        #end
    }
}
