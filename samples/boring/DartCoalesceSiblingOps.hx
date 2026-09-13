package boring;

#if dart_output
/**
 * A constructor whose later default reads an earlier sibling parameter,
 * called from a static method that passes its own locals for both slots.
 * The call-site wrapper must reference the caller-scope argument for the
 * earlier slot, never the callee parameter name (a static method has no
 * such binding in scope).
 */
class DartCoalesceSiblingOps {
    public final base:Float;
    public final derived:Float;

    public function new(?base:Null<Float>, ?derived:Null<Float>) {
        this.base = base == null ? 0.0 : base;
        this.derived = derived == null ? base : derived;
    }

    public static function withValues(corner:Float, continuation:Null<Float>):DartCoalesceSiblingOps {
        return new DartCoalesceSiblingOps(corner, continuation);
    }
}
#else
class DartCoalesceSiblingOps {}
#end
