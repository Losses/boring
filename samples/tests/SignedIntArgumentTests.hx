package tests;

import boring.SignedIntArgumentOps;
import std.Test;

class SignedIntArgumentTests {
    @:test("a negated signed index reinterprets into an owned u32 parameter")
    public static function fromIndex():Void {
        #if rust_output
        Test.equals(5, SignedIntArgumentOps.fromIndex("xbc", 5));
        Test.equals(6, SignedIntArgumentOps.fromIndex("abc", 5));
        #end
    }

    @:test("a signed wrapping sum reinterprets into an owned u32 parameter")
    public static function shifted():Void {
        #if rust_output
        Test.equals(10, SignedIntArgumentOps.shifted("xbc", 5));
        Test.equals(9, SignedIntArgumentOps.shifted("abc", 5));
        #end
    }
}
