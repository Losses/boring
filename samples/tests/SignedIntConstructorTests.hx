package tests;

import boring.SignedIntConstructorOps;
import std.Test;

class SignedIntConstructorTests {
    @:test("a signed wrapping sum reinterprets into an owned u32 constructor slot")
    public static function sumIndex():Void {
        #if rust_output
        Test.equals(5, SignedIntConstructorOps.sumIndex("xbc", 5));
        Test.equals(4, SignedIntConstructorOps.sumIndex("abc", 5));
        #end
    }

    @:test("a negated signed index reinterprets into an owned u32 constructor slot")
    public static function negatedIndex():Void {
        #if rust_output
        Test.equals(0, SignedIntConstructorOps.negatedIndex("xbc"));
        Test.equals(1, SignedIntConstructorOps.negatedIndex("abc"));
        #end
    }
}
