package boring;

#if swift_output
import std.UStringException;
import std.UStringFault;

/**
    `String.indexOf` on a throwing receiver compiles its result inside a
    `map` closure; the duplicated receiver needs its own `try` there.
*/
class ThrowingIndexOfOps {
    public static function text(ok:Bool):String {
        if (!ok)
            throw new UStringException(UStringFault.InvalidCodePoint(1));
        return "in-ter";
    }

    public static function at(ok:Bool):Int
        return text(ok).indexOf("in-ter");
}
#else
class ThrowingIndexOfOps {}
#end
