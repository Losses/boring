package tests;

import boring.NarrowedOptionReturnOps;
import std.Test;

class NarrowedOptionReturnTests {
    @:test("a narrowed nullable value returns through a fallible owned String slot")
    public static function pick():Void {
        #if rust_output
        Test.equals("shown", NarrowedOptionReturnOps.pick("shown"));
        #end
    }
}
