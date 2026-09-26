package boring;

/**
    Regression support for the unsigned-relaxation family around
    intToFloatText: a wrapped Int (a - b with a < b renders
    u32::wrapping_sub on the Rust target) must widen to Float through its
    signed i32 bits, so every context below reads -1.0, not 4294967295.0.
    (SignedIntFloatWiden)
*/
class IntFloatSignOps {
    public static function delta(a:Int, b:Int):Int {
        return a - b;
    }

    // The Int-vs-Float comparison widening (binop).
    public static function belowHalf(a:Int, b:Int):Bool {
        final d = a - b;
        return d < 0.5;
    }

    // The collapsed-local comparison widening.
    public static function equalsCollapsed(a:Int, b:Int):Bool {
        final c:Null<Float> = -1.0;
        if (c == null)
            return false;
        final d = a - b;
        // correct: -1.0 == -1.0; unsigned relaxation reads 4294967295.0
        return d == c;
    }

    // The Float compound-assignment widening.
    public static function compoundSum(a:Int, b:Int):Float {
        var f = 0.5;
        f += a - b;
        return f;
    }

    // The array-literal element widening.
    public static function firstElem(a:Int, b:Int):Float {
        final arr:Array<Float> = [a - b, 2.5];
        return arr[0];
    }

    // The Option<Float> return-boundary widening.
    public static function asOptional(a:Int, b:Int):Null<Float> {
        if (a != b)
            return a - b;
        return null;
    }

    // The has-guarded ternary fallback widening.
    public static function ternaryFallback(a:Int, b:Int):Float {
        final m = new Map<String, Float>();
        m.set("base", 0.5);
        final v = m.get("other");
        // "other" is absent, so the fallback arm must widen the wrapped Int.
        return v != null ? v : (a - b);
    }

    // The value-type constructor Float-representation widening.
    public static function valueCtor(a:Int, b:Int):Float {
        final ic = new Ic(a - b);
        return ic.toPx(1.0);
    }
}
