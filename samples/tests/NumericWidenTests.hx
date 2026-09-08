package tests;

import boring.NumericWidenOps;
import std.Test;

class NumericWidenTests {
    @:test("Int operands widen for Float arithmetic")
    public static function testOperands():Void {
        Test.equals(3.5, NumericWidenOps.operandFloat());
        Test.equals(3.5, NumericWidenOps.operandDouble());
    }

    @:test("Int returns widen for Float results")
    public static function testReturns():Void {
        Test.equals(2.0, NumericWidenOps.returnFloat());
        Test.equals(2.0, NumericWidenOps.returnDouble());
    }

    @:test("Int assignments widen for Float locals")
    public static function testAssignments():Void {
        Test.equals(2.0, NumericWidenOps.assignFloat());
        Test.equals(2.0, NumericWidenOps.assignDouble());
        Test.equals(2.5, NumericWidenOps.appliedFloat());
        Test.equals(2.5, NumericWidenOps.appliedDouble());
    }
}
