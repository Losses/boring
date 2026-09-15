package tests;

import std.Test;

#if rust_output
import boring.ClosureStringViewOps;
#end

class ClosureStringViewOpsTests {
    @:test("a captured String parameter owns text on return")
    public static function testChoose():Void {
        #if rust_output
        Test.equals("found", ClosureStringViewOps.choose(["found"], "fallback"));
        Test.equals("fallback", ClosureStringViewOps.choose([], "fallback"));
        #end
        Test.equals(true, true);
    }

    @:test("a captured String parameter passes a str view through")
    public static function testLabel():Void {
        #if rust_output
        Test.equals("(gamma)", ClosureStringViewOps.label("gamma"));
        #end
        Test.equals(true, true);
    }
}
