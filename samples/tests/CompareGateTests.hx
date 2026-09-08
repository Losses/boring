package tests;

import boring.CompareGateOps;
import std.Test;

/** Regression tests for comparator emission on nested data classes. */
class CompareGateTests {
    @:test("nested data class with Bool remains constructible")
    public static function boolNestedIsUngated():Void {
        Test.equals(true, CompareGateOps.boolNested().inner.enabled);
    }

    @:test("nested data class with supported keys remains constructible")
    public static function safeNestedRemainsComparable():Void {
        Test.equals("a", CompareGateOps.safeNested().value.inner.label);
    }
}
