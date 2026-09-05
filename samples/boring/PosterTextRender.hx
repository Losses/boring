package boring;

import std.RenderShape;

/**
 * The implementing class of the cross-package interface shape: the
 * interface is declared in the std package, this class implements it
 * from the business package, and the tests call RenderShapeTextOps with
 * an instance of this class.
 */
class PosterTextRender implements RenderShape {
    public function new() {}

    public function render(text:String):String {
        return "poster:" + text;
    }
}
