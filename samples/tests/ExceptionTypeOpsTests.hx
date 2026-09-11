package tests;

import std.Test;

#if swift_output
import boring.ExceptionTypeOps;
import std.UStringException;
import std.UStringFault;
#end

class ExceptionTypeOpsTests {
    @:test("a base-typed exception instance is non-null")
    public static function testHasCause():Void {
        #if swift_output
        final cause = new UStringException(UStringFault.InvalidCodePoint(1));
        Test.equals(true, ExceptionTypeOps.hasCause(cause));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a nil base exception argument resolves against the parameter")
    public static function testNilArgument():Void {
        #if swift_output
        Test.equals(false, ExceptionTypeOps.hasCause(null));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a missing base exception ranks against null")
    public static function testMissingCause():Void {
        #if swift_output
        Test.equals(1, ExceptionTypeOps.causeRank(ExceptionTypeOps.missingCause()));
        Test.equals(1, ExceptionTypeOps.causeRank(null));
        #else
        Test.equals(true, true);
        #end
    }
}
