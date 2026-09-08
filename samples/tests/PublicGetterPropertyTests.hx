package tests;

import boring.PublicGetterProperty;
import boring.PublicGetterProperty.HasName;
import std.Test;

class PublicGetterPropertyTests {
    @:test("reads a public property backed by a private getter across modules")
    public static function testPublicGetterProperty():Void {
        Test.equals(8, new PublicGetterProperty(7).x);
    }

    @:test("reads a getter-only property through an interface receiver")
    public static function testGetterOnlyInterfaceRead():Void {
        final h:HasName = new PublicGetterProperty(1);
        Test.equals("getter-property", h.name);
    }

    @:test("reads a getter-only property through a concrete class receiver")
    public static function testGetterOnlyConcreteRead():Void {
        final p = new PublicGetterProperty(1);
        Test.equals("getter-property", p.name);
    }
}
