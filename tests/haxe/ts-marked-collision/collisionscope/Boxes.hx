package collisionscope;

/** The receiver both extension owners query. **/
class Box {
    public final width:Int;

    public function new(width:Int) {
        this.width = width;
    }
}

/**
    The module's file-named type, so its members keep the natural emitted names
    and the other claimant mangles.
**/
class Boxes {
    @:extension
    public static function span(box:Box, from:Int):Int
        return box.width + from;

    @:topLevel
    public static function label(value:Int):Int
        return value + 1;
}

/**
    The second claimant of both marked names. TypeScript gives the module file
    one namespace, so two exported declarations of one name collide
    (TS2323/TS2393). The shapes come from tiqian's engine, whose
    LayoutQueryFns.hx declares the TextRange and Int-pair getBoundingBoxes
    extensions in one module and failed the npm pack with exactly that pair.
**/
class BoxSpanRangeFns {
    @:extension
    public static function span(box:Box, from:Int, to:Int):Int
        return box.width + from + to;

    @:topLevel
    public static function label(value:String):Int
        return value.length;
}
