package tests;

import boring.ValuePassingOps;
import std.Test;

class ValuePassingTests {
    @:test("field reads and parameter passes keep values usable")
    public static function valueFlow():Void {
        var card = ValuePassingOps.buildCard();
        Test.equals("card|card", ValuePassingOps.readTwoFields(card));
        Test.equals(4, ValuePassingOps.passTwice(card));
        Test.equals(9, ValuePassingOps.forwardParameter(card.tags));
        Test.equals("added", ValuePassingOps.pushThrough(card.tags));
        Test.equals(9, ValuePassingOps.lengthArithmetic("four"));
    }
}
