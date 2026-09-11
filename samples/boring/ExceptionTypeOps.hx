package boring;

/**
 * Declared uses of the shared haxe.Exception base (features/06). The
 * base class maps to the runtime BoringException, so a parameter typed
 * as the base, an optional base parameter, and a nil argument all
 * resolve in Swift.
 */
class ExceptionTypeOps {
    public static function hasCause(cause:Null<haxe.Exception>):Bool {
        return cause != null;
    }

    public static function missingCause():Null<haxe.Exception> {
        return null;
    }

    public static function causeRank(cause:Null<haxe.Exception>):Int {
        return cause == null ? 1 : 0;
    }
}
