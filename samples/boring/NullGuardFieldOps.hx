package boring;

#if swift_output
/**
    A null comparison whose tested operand is a field access narrows the
    field in the matched ternary arm. Haxe emits `(field != null ? field :
    fallback)`; Swift keeps the arm optional and the ternary no longer fits
    a non-optional context. The emitter lowers both arm orders to `??`.
*/
class NullGuardFieldOps {
    /** `field != null ? field : fallback` on an instance field. */
    public static function fieldAscent(m:NullGuardFieldMetrics):Float {
        return m.typoAscent != null ? m.typoAscent : m.ascent;
    }

    /** `field == null ? fallback : field` on an instance field. */
    public static function fieldReason(m:NullGuardFieldMetrics, fallback:String):String {
        return m.reason == null ? fallback : m.reason;
    }
}
#else
class NullGuardFieldOps {}
#end
