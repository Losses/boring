package tests;

import boring.SwitchOps;
import std.Test;

class SwitchOpsTests {

    @:test("switch assign position lowers")
    public static function testAssign():Void {
        Test.equals("empty", SwitchOps.assign(Empty));
        Test.equals("text:y", SwitchOps.assign(Text("y")));
    }

    @:test("switch statement assignment lowers")
    public static function testStatement():Void {
        Test.equals("empty", SwitchOps.statement(Empty));
        Test.equals("number:3", SwitchOps.statement(Number(3)));
        Test.equals("text:x", SwitchOps.statement(Text("x")));
    }

    @:test("switch initializer lowers")
    public static function testInitializer():Void {
        Test.equals("number:4", SwitchOps.initializer(Number(4)));
    }

    @:test("switch default lowers")
    public static function testDefault():Void {
        Test.equals("empty", SwitchOps.defaulted(Empty));
        Test.equals("fallback", SwitchOps.defaulted(Other));
    }
}
