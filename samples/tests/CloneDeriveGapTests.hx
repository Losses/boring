package tests;

import boring.CloneDeriveGapOps;
import std.Test;

class CloneDeriveGapTests {
    @:test("data class holding a plain-class field derives Clone and reads owned values")
    public static function resolve():Void {
        Test.equals("1..3:x", CloneDeriveGapOps.resolve([
            new boring.CloneDeriveResult(new boring.CloneDeriveRange(1, 3), "x")
        ]));
    }

    @:test("class holding a string abstract field derives Clone and reads owned values")
    public static function resolveAbstract():Void {
        Test.equals("x:2", CloneDeriveGapOps.resolveAbstract([
            new boring.CloneDeriveAbstractResult("x", 2)
        ]));
    }
}
