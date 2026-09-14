package tests;

import boring.FloatFieldLiteralOps;
import std.Test;

class FloatFieldLiteralOpsTests {
    @:test("an Int literal widens into an anonymous Float field")
    public static function pair():Void {
        #if rust_output
        final leading = FloatFieldLiteralOps.pair(0, 2.0);
        Test.equals(2.0, leading.leading);
        Test.equals(0.0, leading.trailing);
        final trailing = FloatFieldLiteralOps.pair(1, 3.0);
        Test.equals(0.0, trailing.leading);
        Test.equals(3.0, trailing.trailing);
        final both = FloatFieldLiteralOps.pair(2, 4.0);
        Test.equals(2.0, both.leading);
        Test.equals(2.0, both.trailing);
        #end
    }
}
