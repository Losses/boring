package tests;

import boring.ParseIntPushOps;
import std.Test;

class ParseIntPushTests {
    @:test("a direct Std.parseInt result pushes into a u32 array")
    public static function parseAll():Void {
        #if rust_output
        final values = ParseIntPushOps.parseAll(["1", "2", "3"]);
        Test.equals(3, values.length);
        Test.equals(1, values[0]);
        Test.equals(2, values[1]);
        Test.equals(3, values[2]);
        #end
    }

    @:test("a local Std.parseInt result pushes into a u32 array")
    public static function parseLocal():Void {
        #if rust_output
        final values = ParseIntPushOps.parseLocal(["4", "5"]);
        Test.equals(2, values.length);
        Test.equals(4, values[0]);
        Test.equals(5, values[1]);
        #end
    }
}
