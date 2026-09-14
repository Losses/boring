package tests;

import boring.InterfaceFallibleOps;
import std.Test;

class InterfaceFallibleOpsTests {
    @:test("a call through a throwing interface method propagates its error")
    public static function value():Void {
        #if rust_output
        Test.equals("value3", InterfaceFallibleOps.value(3));
        #end
    }
}
