package boring;

import boring.ShapeTextOps.TextShaper;

/**
 * The implementing class of the cross-module interface shape: the
 * interface is declared in ShapeTextOps, this class implements it from
 * a second module, and the tests call ShapeTextOps.render with an
 * instance of this class.
 */
class InkTextShaper implements TextShaper {
    public function new() {}

    public function shape(text:String):String {
        return "ink:" + text;
    }
}
