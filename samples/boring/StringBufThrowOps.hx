package boring;

import std.StringBuf;
import std.UStringException;
import std.UStringFault;

/**
 * StringBuf operations whose added value comes from a throwing call
 * (stdlib/08). The checked add reads its argument's first UTF-16 unit
 * inside the surrogate guard, so the argument's fallibility reaches the
 * guard condition and the append; the checked addChar reads its argument
 * unit in the same guard.
 */
class StringBufThrowOps {
    static function checkedLabel(count:Int):String {
        if (count == 0) {
            throw new UStringException(UStringFault.InvalidCodePoint(11));
        }
        return "item-" + count;
    }

    static function classifyFault(fault:UStringFault):Int {
        return switch (fault) {
            case InvalidCodePoint(code): 3000 + code;
            case UnpairedSurrogate(unit): 4000 + unit;
        };
    }

    /** The added string is the result of a throwing call. */
    public static function buildFromChecked(count:Int):String {
        final buf = new StringBuf();
        buf.add(checkedLabel(count));
        return buf.toString();
    }

    /** The fault of the added call travels out of the buffer expression. */
    public static function caughtChecked(count:Int):Int {
        final value = try {
            final buf = new StringBuf();
            buf.add(checkedLabel(count));
            0;
        } catch (error:UStringException) {
            classifyFault(error.fault);
        };
        return value;
    }

    static function checkedUnit(count:Int):Int {
        if (count == 0) {
            throw new UStringException(UStringFault.InvalidCodePoint(13));
        }
        return 0x41;
    }

    /** The added unit is the result of a throwing call. */
    public static function buildCharFromChecked(count:Int):String {
        final buf = new StringBuf();
        buf.addChar(checkedUnit(count));
        return buf.toString();
    }
}
