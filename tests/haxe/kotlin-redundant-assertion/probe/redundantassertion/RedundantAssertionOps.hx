package redundantassertion;

/**
    The minimal shape of `packages/compiler/runtime/StringTools.hx`'s
    `isSpace` tail: one immutable nullable local read more than once inside
    one expression.

    `charCodeAt` lowers to `run { ... else null }`, so `c` has Kotlin storage
    `Int?`. The first read `c > 8` forces it (`c!!`); Kotlin's data-flow
    analysis then holds `c` non-null for the rest of the dominating region,
    because `c` is a `val` local that is never reassigned. Whether the emitter
    prints an assertion on each later read is the measurement.
    (RedundantAssertionCoverage)
**/
class RedundantAssertionOps {
    /** The measured shape, byte-for-byte the tail of `StringTools.isSpace`. */
    public static function isSpace(s:String, pos:Int):Bool {
        if (s.length == 0 || pos < 0 || pos >= s.length) {
            return false;
        }
        final c = s.charCodeAt(pos);
        return (c > 8 && c < 14) || c == 32;
    }

    /** Control: the two `&&` reads alone, no `||` tail. */
    public static function lowerBound(s:String, pos:Int):Bool {
        final c = s.charCodeAt(pos);
        return c > 8 && c < 14;
    }

    /** Control: the two reads separated by statements, so the second read is
        still dominated by the first assertion but is not a sibling operand. */
    public static function threeReads(s:String, pos:Int):Bool {
        final c = s.charCodeAt(pos);
        final above = c > 8;
        final below = c < 14;
        return above && below;
    }

    /** Control: the equality read first. Equality is null-safe in Kotlin, so
        this read takes no assertion whatever the proof state -- which is why
        the third read of `isSpace` is correct for a reason of its own and not
        evidence that the proof mechanism reached it. */
    public static function eqRead(s:String, pos:Int):Bool {
        final c = s.charCodeAt(pos);
        return c == 32;
    }

    /** Safety control for any fix: the two ternary arms are siblings, neither
        dominating the other, so both reads must keep their assertion. A
        suppression that ignores arm scoping would drop the second one and
        kotlinc would reject the result. */
    public static function armRead(s:String, pos:Int, flag:Bool):Bool {
        final c = s.charCodeAt(pos);
        return flag ? c > 8 : c < 14;
    }
}
