package tests;

import boring.PrivateStaticCallOps;
import std.Test;

class PrivateStaticCallTests {
    @:test("private static referenced by class name lowers under its Dart name")
    public static function testPrivateStaticCall():Void {
        Test.equals("empty", PrivateStaticCallOps.render());
    }
}