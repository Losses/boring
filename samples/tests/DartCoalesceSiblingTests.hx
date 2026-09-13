package tests;

import std.Test;

#if dart_output
import boring.DartCoalesceSiblingOps;
#end

class DartCoalesceSiblingTests {
    @:test("a static call site binds sibling defaults to caller arguments")
    public static function testSibling():Void {
        #if dart_output
        Test.equals(3.0, DartCoalesceSiblingOps.withValues(3.0, null).derived);
        Test.equals(3.0, DartCoalesceSiblingOps.withValues(3.0, null).base);
        Test.equals(4.0, DartCoalesceSiblingOps.withValues(3.0, 4.0).derived);
        #else
        Test.equals(true, true);
        #end
    }
}
