package tests;

import boring.PublicGetterProperty;
import std.Test;

class PublicGetterPropertyTests {
    @:test("reads a public property backed by a private getter across modules")
    public static function testPublicGetterProperty():Void {
        Test.equals(8, new PublicGetterProperty(7).x);
    }
}
