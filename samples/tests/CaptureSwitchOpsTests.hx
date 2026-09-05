package tests;

import boring.CaptureSwitchOps;
import boring.CaptureSwitchOps.CaptureSwitchValue;
import boring.CaptureSwitchOps.NoSuchElementError;
import std.Test;

class CaptureSwitchOpsTests {
    @:test("single captured switch forwards a return payload")
    public static function testDescribe():Void {
        Test.equals("gone", CaptureSwitchOps.describe(NoSuchElementError.Message("gone")));
    }

    @:test("single captured switch works in an initializer")
    public static function testInitialized():Void {
        Test.equals("ready", CaptureSwitchOps.initialized(NoSuchElementError.Message("ready")));
    }

    @:test("multi-case captured switch remains available")
    public static function testClassify():Void {
        Test.equals(3, CaptureSwitchOps.classify(CaptureSwitchValue.Text("abc")));
        Test.equals(8, CaptureSwitchOps.classify(CaptureSwitchValue.Number(7)));
    }

    @:test("single captured payload supports an operation")
    public static function testMessageLength():Void {
        Test.equals(5, CaptureSwitchOps.messageLength(NoSuchElementError.Message("test")));
    }
}
