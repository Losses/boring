package boring;

/**
 * Regression sample for Float array local bindings in f32 mode.
 * A local `final` with an explicit Array<Float> type and a float-literal
 * initializer must carry a type annotation in the Swift output; without
 * it Swift infers [Double] and the call site fails with a type mismatch.
 */
class FloatArrayAnnoOps {
    public static function sumOf(values:Array<Float>):Float {
        var total:Float = 0.0;
        for (v in values) {
            total += v;
        }
        return total;
    }

    public static function verify():Bool {
        final floats:Array<Float> = [1.5, 2.0, 3.5];
        return sumOf(floats) == 7.0;
    }
}
