package tests;

import boring.StringToolsOps;
import std.Test;

class StringToolsTests {
    @:test("lpad pads on the left through the runtime module")
    public static function padLeft():Void {
        Test.equals("0000ab", StringToolsOps.padLeft("ab", 6));
    }

    @:test("ltrim and rtrim strip whitespace through the runtime module")
    public static function trims():Void {
        Test.equals("ab  ", StringToolsOps.ltrim("  ab  "));
        Test.equals("  ab", StringToolsOps.rtrim("  ab  "));
    }

    @:test("replace swaps substrings through the runtime module")
    public static function replace():Void {
        Test.equals("a,b,c", StringToolsOps.replaceDelims("a;b;c"));
    }
}
