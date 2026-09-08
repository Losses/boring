package tests;

import boring.StaticRefOps;
import std.Test;

class StaticRefTests {
    @:test("static method passed as value to function-typed parameter")
    public static function testPassToParam():Void {
        Test.equals("code:42", StaticRefOps.passToParam());
    }

    @:test("static method stored in function-typed local")
    public static function testStoreLocal():Void {
        Test.equals("code:42", StaticRefOps.storeLocal());
    }

    @:test("static method returned as function value")
    public static function testReturnFn():Void {
        Test.equals("code:42", StaticRefOps.returnFn()(42));
    }

    @:test("static method assigned in function-typed local")
    public static function testReassignLocal():Void {
        Test.equals("code:42", StaticRefOps.reassignLocal());
    }

    @:test("statics-only class static method used as value")
    public static function testStaticsOnlyValue():Void {
        Test.equals(1, StaticRefOps.staticsOnlyValue());
    }

    @:test("static method at call site is unchanged")
    public static function testCallSite():Void {
        Test.equals("code:42", StaticRefOps.callSite());
    }
}
