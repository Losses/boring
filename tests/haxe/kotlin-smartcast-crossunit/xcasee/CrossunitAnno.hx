package xcasee;

import casee.Holder;
import casee.Vec;
import casee.Support;

class CrossunitAnno {
    /** cross-unit: nullable Main-unit field read as a call receiver. */
    @:test
    public static function receiverPath():Void {
        final c = new Holder(new Vec(1.0));
        if (c.value != null) {
            final mag = c.value.magnitude();
        }
    }

    /** cross-unit: nullable Main-unit field passed to a non-null param. */
    @:test
    public static function argumentPath():Void {
        final c = new Holder(new Vec(2.0));
        if (c.value != null) {
            final mag = Support.useVec(c.value);
        }
    }

    /** cross-unit: separate unguarded statements (tiqian line 39-52 shape). */
    @:test
    public static function separateStatements():Void {
        final c = new Holder(new Vec(3.0));
        final a = Support.useVec(c.value);
        final b = Support.useVec(c.value);
        final d = c.value.magnitude();
        final e = Support.useVec(c.value);
    }

    /** cross-unit: wasNotNull + ternary (tiqian line 36-38 shape). */
    @:test
    public static function ternaryShape():Void {
        final c = new Holder(new Vec(4.0));
        final wasNotNull = c.value != null;
        final label = c.value == null ? "null" : Std.string(Support.useVec(c.value));
        final f = Support.useVec(c.value);
    }
}
