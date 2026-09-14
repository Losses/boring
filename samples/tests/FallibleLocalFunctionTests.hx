package tests;

import std.Test;

#if rust_output
import boring.FallibleLocalFunctionOps;
import boring.FallibleLocalFunctionOps.FallibleLocalFunctionFault;
#end

class FallibleLocalFunctionTests {
    @:test("a Void local function that throws propagates through the enclosing Result")
    public static function localVoidThrow():Void {
        #if rust_output
        var caught = "";
        try {
            FallibleLocalFunctionOps.guard(5, 4);
        } catch (error:FallibleLocalFunctionFault) {
            caught = error.message;
        }
        Test.equals("over limit", caught);
        #else
        Test.equals(true, true);
        #end
    }

    @:test("the infallible path returns the guarded value")
    public static function localVoidSuccess():Void {
        #if rust_output
        Test.equals(3, FallibleLocalFunctionOps.guard(3, 4));
        #else
        Test.equals(true, true);
        #end
    }
}
