package tests;

import std.Test;

#if rust_output
import boring.ResidentBuilderInferOps;
#end

class ResidentBuilderInferOpsTests {
    @:test("a resident builder binds its key and value types")
    public static function testResidentBuilder():Void {
        #if rust_output
        Test.equals(3, ResidentBuilderInferOps.sum());
        #end
        Test.equals(true, true);
    }
}
