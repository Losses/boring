package tests;

import boring.NegIntSlotOps;
import std.Test;

class NegIntSlotOpsTests {
    @:test("a negated Int reinterprets at the u32 return and argument slots")
    public static function negate():Void {
        #if rust_output
        Test.equals(-5, NegIntSlotOps.negate(5), "direct negation");
        Test.equals(-7, NegIntSlotOps.negateArgument(7), "negated argument");
        Test.equals(0, NegIntSlotOps.negate(0), "zero negation");
        #end
    }

    @:test("a negated conditional arm carries the u32 slot type")
    public static function negateConditional():Void {
        #if rust_output
        Test.equals(-3, NegIntSlotOps.negateConditional(true, 3), "negative arm");
        Test.equals(4, NegIntSlotOps.negateConditional(false, 4), "positive arm");
        #end
    }
}
