package tests;

import boring.ExceptionTypeOps;
import std.Test;
import std.UStringException;
import std.UStringFault;

class ExceptionTypeOpsTests {
    @:test("a base-typed exception instance is non-null")
    public static function testHasCause():Void {
        final cause = new UStringException(UStringFault.InvalidCodePoint(1));
        Test.equals(true, ExceptionTypeOps.hasCause(cause));
    }

    @:test("a nil base exception argument resolves against the parameter")
    public static function testNilArgument():Void {
        Test.equals(true, ExceptionTypeOps.hasCause(null));
    }

    @:test("a missing base exception ranks against null")
    public static function testMissingCause():Void {
        Test.equals(1, ExceptionTypeOps.causeRank(ExceptionTypeOps.missingCause()));
        Test.equals(1, ExceptionTypeOps.causeRank(null));
    }
}
