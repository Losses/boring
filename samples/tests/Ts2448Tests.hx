package tests;

import boring.Ts2448Ops;
import std.Test;

class Ts2448Tests {
    @:test("nested locals do not self-reference")
    public static function nestedLocal():Void {
        Test.equals(2, Ts2448Ops.nestedLocal());
    }
}
