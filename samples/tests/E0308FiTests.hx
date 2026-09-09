package tests;

import boring.E0308FiOps;
import std.Test;

class E0308FiTests {
    @:test("local boolean closure keeps its value result")
    public static function testLocalBool():Void {
        Test.equals(true, E0308FiOps.localBool());
    }

    @:test("instance receiver return is owned")
    public static function testOwnedReceiver():Void {
        Test.equals(true, new E0308FiOps().returnOwned() != null);
    }

    @:test("nullable float narrowing preserves the value")
    public static function testOptionalFloat():Void {
        Test.equals(2.5, E0308FiOps.optionalFloat(2.5));
        Test.equals(0.0, E0308FiOps.optionalFloat(null));
    }
}
