package tests;

import boring.ExtensionConsumer;
import boring.ExtensionOps;
import boring.ExtensionOps.ExtensionMode;
import boring.FileLevelConsumer;
import boring.FileLevelOps;
import std.Test;

/** Runtime hooks for the top-level and extension declaration forms. */
class StaticExtensionTests {
    @:test("top-level functions cross module boundaries")
    public static function testTopLevelResults():Void {
        Test.equals(17, FileLevelConsumer.publicResult());
        Test.equals(23, FileLevelConsumer.privateResultThroughPublic());
        Test.equals(17, FileLevelOps.publicValue(7));
    }

    @:test("owned extension renders and evaluates as a receiver method")
    public static function testOwnedExtension():Void {
        Test.equals("hot!", ExtensionConsumer.enumResult());
        Test.equals("private-cold", ExtensionConsumer.privateResult());
        Test.equals("cold?", ExtensionOps.modeLabel(ExtensionMode.Cold, "?"));
    }

    @:test("foreign string extension keeps its receiver argument")
    public static function testStringExtension():Void {
        Test.equals("@core", ExtensionConsumer.stringResult());
        Test.equals("#text", ExtensionOps.stringLabel("text", "#"));
    }
}
