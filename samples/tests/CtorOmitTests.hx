package tests;

import std.Test;
import boring.CtorOmitOps;

class CtorOmitTests {
    @:test("constructor omitted trailing defaults materialize")
    public static function testOmit():Void {
        Test.equals(true, CtorOmitOps.make() > 0.0);
    }
}
