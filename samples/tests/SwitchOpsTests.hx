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

    @:test("switch inside a conditional arm lowers")
    public static function testConditional():Void {
        Test.equals("fallback", SwitchOps.conditional(Empty, true));
        Test.equals("empty", SwitchOps.conditional(Empty, false));
        Test.equals("number:3", SwitchOps.conditional(Number(3), false));
        Test.equals("text:x", SwitchOps.conditional(Text("x"), false));
    }
}
