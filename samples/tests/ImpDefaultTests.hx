package tests;

import boring.ImpHost;
import boring.ImpWidget;
import std.Test;

class ImpDefaultTests {
    @:test("materialized cross-package constructor default")
    public static function defaults():Void {
        Test.equals("w", new ImpHost(null).widget.label);
        Test.equals("x", new ImpHost(new ImpWidget("x")).widget.label);
    }
}
