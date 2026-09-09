package tests;

import boring.SwiftDefaultOps;
import std.Test;

class SwiftDefaultTests {
    @:test("data class defaults construct a value type static constant")
    public static function testDefaultStyle():Void {
        Test.equals(true, SwiftDefaultOps.hasDefault());
    }
}
