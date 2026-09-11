package boring;

#if swift_output
import std.UStringException;
import std.UStringFault;

/**
 * Locally declared functions that throw. A local function body is not a
 * class field, so the call sites read the per-body fallibility before
 * they can carry the try marker. The shape is Swift-side: the other
 * targets lower local throwing functions through their own error
 * carrier.
 */
class LocalThrowOps {
    static function classify(fault:UStringFault):Int {
        return switch (fault) {
            case InvalidCodePoint(code): 5000 + code;
            case UnpairedSurrogate(unit): 6000 + unit;
        };
    }

    /** The local function throws directly; its call needs try. */
    public static function localStep(count:Int):Int {
        function step(value:Int):Int {
            if (value == 0) {
                throw new UStringException(UStringFault.InvalidCodePoint(7));
            }
            return value + 1;
        }
        return step(count);
    }

    /** The local function throws through a call to another local function. */
    public static function localNested(count:Int):Int {
        function step(value:Int):Int {
            if (value == 0) {
                throw new UStringException(UStringFault.InvalidCodePoint(9));
            }
            return value + 1;
        }
        function double(value:Int):Int {
            return step(value) * 2;
        }
        return double(count);
    }

    /** The local call is the whole condition of a return. */
    public static function localCondition(count:Int):Bool {
        function positive(value:Int):Bool {
            if (value == 0) {
                throw new UStringException(UStringFault.InvalidCodePoint(11));
            }
            return value > 0;
        }
        return positive(count);
    }

    /** The local call sits inside an array literal. */
    public static function localArray(count:Int):Array<Int> {
        function step(value:Int):Int {
            if (value == 0) {
                throw new UStringException(UStringFault.InvalidCodePoint(13));
            }
            return value + 1;
        }
        return [step(count)];
    }

    /** A caught local fault reaches the caller through the class function. */
    public static function caughtLocal(count:Int):Int {
        final value = try {
            localStep(count);
        } catch (error:UStringException) {
            classify(error.fault);
        };
        return value;
    }
}
#else
class LocalThrowOps {}
#end
