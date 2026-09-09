package tests;

import boring.NumericWidenOps;
import boring.SwitchMergeOps.SwitchMergeValue;
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
        Test.equals(1.0, NumericWidenOps.appliedDouble());
    }

    @:test("Nullable conditional arms widen for Float results")
    public static function testNullableConditional():Void {
        Test.equals(2.5, NumericWidenOps.nullableConditional(2.5));
        Test.equals(0.0, NumericWidenOps.nullableConditional(null));
    }

    @:test("Conditional and switch arms widen for Float results")
    public static function testBranchMerges():Void {
        Test.equals(1.5, NumericWidenOps.conditionalMerge(true));
        Test.equals(2.0, NumericWidenOps.conditionalMerge(false));
        Test.equals(1.5, NumericWidenOps.switchMerge(SwitchMergeValue.First(1)));
        Test.equals(2.0, NumericWidenOps.switchMerge(SwitchMergeValue.Second(1)));
        Test.equals(0.5, NumericWidenOps.switchMerge(SwitchMergeValue.Third));
    }
}
