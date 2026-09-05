package tests;

import boring.InkTextShaper;
import boring.ShapeTextOps;
import std.Test;

class ShapeTextTests {
    @:test("an instance of the cross-module implementing class satisfies the interface parameter")
    public static function render():Void {
        Test.equals("ink:hi", ShapeTextOps.render(new InkTextShaper(), "hi"));
    }
}
