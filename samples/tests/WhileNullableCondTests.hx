package tests;

import boring.WhileNullableCond;
import std.Test;

class WhileNullableCondTests {
    @:test("a Null<Bool> condition drives a while loop (null is falsy)")
    public static function whileOnNullableCond():Void {
        Test.equals(3, WhileNullableCond.f(true));
        Test.equals(0, WhileNullableCond.f(false));
        Test.equals(0, WhileNullableCond.f(null));
    }
}

