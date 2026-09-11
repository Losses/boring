package boring;

/**
 * A haxe.Exception parameter type lowers to the native Error type
 * on TypeScript, so accessing `.message` must fold to the native
 * property without emitting a relative import for the Haxe extern.
 **/
class ExceptionCatchOps {
    public static function causeMessage(cause: Null<haxe.Exception>): String {
        if (cause == null) {
            return "none";
        }
        return cause.message;
    }
}
