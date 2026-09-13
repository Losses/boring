package tests;

import boring.MutatingCounterOps;
import std.Test;

class MutatingCounterTests {
    @:test("a mutating interface method forces the mutable receiver on the trait object")
    public static function bumpTwice():Void {
        Test.equals(3, MutatingCounterOps.bumpTwice());
    }

    @:test("a read-only implementation keeps the aggregated mutable trait shape")
    public static function readOnly():Void {
        Test.equals(0, MutatingCounterOps.readOnly());
    }

    @:test("a concrete receiver accumulates through a compound field update")
    public static function concreteBump():Void {
        Test.equals(3, MutatingCounterOps.bumpThriceConcrete());
    }
}
