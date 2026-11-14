package collisionscope;

import collisionscope.Boxes.Box;
import collisionscope.Boxes.BoxSpanRangeFns;

/**
    Cross-class call sites: the plain static calls must resolve to the emitted
    spelling of their own declaring class.
**/
class BoxProbe {
    public static function naturalSpan(box:Box, from:Int):Int
        return Boxes.span(box, from);

    public static function contestedSpan(box:Box, from:Int, to:Int):Int
        return BoxSpanRangeFns.span(box, from, to);

    public static function naturalLabel(value:Int):Int
        return Boxes.label(value);

    public static function contestedLabel(value:String):Int
        return BoxSpanRangeFns.label(value);
}
