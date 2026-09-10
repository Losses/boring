package tests;

import boring.CloneDeriveGapOps;
import std.Test;

class CloneDeriveGapTests {
    @:test("data class holding a plain-class field derives Clone and reads owned values")
    public static function resolve():Void {
        Test.equals(3, CloneDeriveGapOps.resolve());
    }
}