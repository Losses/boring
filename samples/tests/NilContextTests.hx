package tests;

import boring.NilContextOps;
import std.Test;

class NilContextTests {
    @:test("conditional nil retains its optional payload")
    public static function testConditional():Void {
        Test.equals("present", NilContextOps.conditional(true));
        Test.equals(null, NilContextOps.conditional(false));
    }

    @:test("synthesized optional argument nil is typed")
    public static function testArgument():Void {
        Test.equals("empty", NilContextOps.nullArgument());
    }
}
