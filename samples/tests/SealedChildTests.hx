package tests;

import boring.SealedChildOps;
import std.Test;

class SealedChildTests {
    @:test("a message-only child of a folded parent keeps the delegated message")
    public static function childMessage():Void {
        #if kotlin_output
        Test.equals("sealed child message", SealedChildOps.childMessage("sealed child message"));
        #else
        Test.equals("sealed child message", SealedChildOps.childMessage("sealed child message"));
        #end
    }
}
