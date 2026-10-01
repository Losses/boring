package casee;

/**
    casee probe for PIT-388.

    Kotlin smart-casts `recv.field` only when BOTH halves hold:

      * the field renders as a `val` -- a `var` property is never
        smart-castable, so `varField` below is a negative control for the
        field half; and
      * the receiver chain's root local is one Kotlin treats as stable -- a
        local this body rebinds, or one a capturing closure writes, makes
        every `recv.field` projection a non-stable value, so `betweenWrite`
        and `closureWrite` are negative controls for the receiver half.

    An emitter that decides the whole question from the guard's flow proof
    alone emits a plain dot in all four shapes and kotlinc rejects three of
    them:
      * betweenWrite -> "only safe (?.) or non-null asserted (!!.) calls are
        allowed on a nullable receiver of type 'Vec?'"
      * closureWrite -> "smart cast to 'Vec' is impossible, because 'value'
        is a local variable that is mutated in a capturing closure."
      * varField     -> "smart cast to 'Vec' is impossible, because 'value'
        is a mutable property that could be mutated concurrently."

    `stableFinal` and `writeBeforeGuard` are over-reach controls. Kotlin's
    data flow *does* prove both of them, so the plain dot must stay: hardening
    them instead would trade the error for an "unnecessary non-null assertion
    (!!)" warning, and the warning count is part of acceptance.
**/
class CaseEOps {
    /** Negative: the root local is written between the guard and the use. */
    public static function betweenWrite(flag:Bool):Float {
        var a = new Holder(new Vec(1.0));
        if (a.value != null) {
            if (flag) {
                a = new Holder(null);
            }
            return a.value.magnitude();
        }
        return 0.0;
    }

    /** Negative: the root local is written from a capturing closure. */
    public static function closureWrite(flag:Bool):Float {
        var a = new Holder(new Vec(1.0));
        final bump:Void->Void = function() {
            a = new Holder(null);
        };
        touch(bump, flag);
        if (a.value != null) {
            return a.value.magnitude();
        }
        return 0.0;
    }

    static function touch(f:Void->Void, call:Bool):Void {
        if (call) {
            f();
        }
    }

    /** Negative: the field is a Kotlin `var` property, so never smart-castable. */
    public static function varField():Float {
        final m = new MutableHolder(new Vec(1.0));
        if (m.value != null) {
            return m.value.magnitude();
        }
        return 0.0;
    }

    /** Over-reach control: final field on a never-reassigned root. */
    public static function stableFinal():Float {
        final c = new Holder(new Vec(2.0));
        if (c.value != null) {
            return c.value.magnitude();
        }
        return 0.0;
    }

    /**
        Over-reach control: the root is written, but only *before* the guard.
        Kotlin's data flow still proves the read, so an added `!!` here would
        be an `unnecessary non-null assertion` warning.
    **/
    public static function writeBeforeGuard():Float {
        var a = new Holder(new Vec(1.0));
        a = new Holder(new Vec(3.0));
        if (a.value != null) {
            return a.value.magnitude();
        }
        return 0.0;
    }
}
