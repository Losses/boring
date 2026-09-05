package tests;

import boring.PosterTextRender;
import boring.RenderShapeTextOps;
import std.Test;

class PosterShapeTests {
    @:test("a class in the business package implements a std-package interface")
    public static function print():Void {
        Test.equals("poster:hi", RenderShapeTextOps.print(new PosterTextRender(), "hi"));
    }
}
