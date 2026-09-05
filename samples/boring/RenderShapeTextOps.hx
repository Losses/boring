package boring;

import std.RenderShape;

class RenderShapeTextOps {
    public static function print(shape:RenderShape, text:String):String {
        return shape.render(text);
    }
}
