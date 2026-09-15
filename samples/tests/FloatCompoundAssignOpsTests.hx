package tests;

import boring.FloatCompoundAssignOps;
import std.Test;

class FloatCompoundAssignOpsTests {
    @:test("a Float compound assignment widens an Int right side")
    public static function scaled():Void {
        #if rust_output
        Test.equals(true, FloatCompoundAssignOps.scaled(250.0) == 2.5);
        Test.equals(true, FloatCompoundAssignOps.scaled(0.25) == 2.5);
        #end
    }

    @:test("a Float accumulator widens each Int increment")
    public static function stepTotal():Void {
        #if rust_output
        Test.equals(true, FloatCompoundAssignOps.stepTotal() == 3.0);
        #end
    }

    @:test("add and subtract compound assignments widen Int right sides")
    public static function walk():Void {
        #if rust_output
        Test.equals(true, FloatCompoundAssignOps.walk(5.0) == 6.0);
        #end
    }
}
