package tests;

import boring.OptionalCtorOps;
import std.Test;

class OptionalCtorTests {
    @:test("optional nullable ctor params with differently-named fields render optional")
    public static function testOptionalCtor():Void {
        Test.equals("default/7|x/3", OptionalCtorOps.render());
    }
}