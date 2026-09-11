package tests;

import std.Test;

#if swift_output
import boring.ThrowingClosureOps;
import std.UStringException;
import std.UStringFault;
#end

class ThrowingClosureTests {
    @:test("a throwing closure matches a zero-argument Void callback")
    public static function testThrowingClosure():Void {
        #if swift_output
        Test.equals(0, ThrowingClosureOps.caught(function() {}));
        Test.equals(1, ThrowingClosureOps.caught(function() {
            throw new UStringException(UStringFault.InvalidCodePoint(3));
        }));
        #else
        Test.equals(true, true);
        #end
    }
}
