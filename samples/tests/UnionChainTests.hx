package tests;

import std.Test;

#if rust_output
import boring.HaxeExceptionOps.HaxeExceptionFault;
import boring.UnionChainOps;
import boring.ValueException;
#end

class UnionChainTests {
    @:test("a repeated callee union stays convertible through a chained caller")
    public static function chainedUnion():Void {
        #if rust_output
        Test.equals(5, UnionChainOps.outer(5));

        var alphaCaught = false;
        try {
            UnionChainOps.outer(-1);
        } catch (error:HaxeExceptionFault) {
            alphaCaught = true;
        }
        Test.equals(true, alphaCaught);

        var betaCaught = false;
        try {
            UnionChainOps.outer(11);
        } catch (error:ValueException) {
            betaCaught = true;
        }
        Test.equals(true, betaCaught);
        #else
        Test.equals(true, true);
        #end
    }
}
