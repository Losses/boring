package trees;

import std.Test;

/** The test-tree referencer: while this class is the only name that reaches
  Shared, the single-pass closure classifies Shared as test code. */
class SharedTest {
    @:test public static function describeKeepsLabel():Void {
        Test.equals("shared:alpha", new Shared("alpha").describe(), "label");
    }
}
