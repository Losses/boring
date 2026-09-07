package tests;

import boring.SwiftLiteralSafetyOps;
import std.Test;

class SwiftLiteralSafetyOpsTests {
    @:test("trailing-point float literal renders as zero")
    public static function testTrailingPoint():Void {
        Test.equals(0.0, SwiftLiteralSafetyOps.trailingPoint());
    }

    @:test("control character in literal renders escaped")
    public static function testControlText():Void {
        Test.equals("before" + String.fromCharCode(8) + "after", SwiftLiteralSafetyOps.controlText());
    }
}
