package tests;

import std.Test;

#if rust_output
import boring.NarrowedSortedReceiverOps;
#end

class NarrowedSortedReceiverOpsTests {
    @:test("a nullable sorted receiver keeps the null-coalescing binding")
    public static function testNarrowedReceiver():Void {
        #if rust_output
        Test.equals(false, NarrowedSortedReceiverOps.hasKey(null, "a"));
        Test.equals(0, NarrowedSortedReceiverOps.sizeOrZero(null));
        #end
        Test.equals(true, true);
    }
}
