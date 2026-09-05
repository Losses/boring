package boring;

/**
 * Reads the message text of a folded exception class from a plain
 * parameter position, not a catch variable: the runtime-dependent
 * get_message lowering must map to the sealed class's native message
 * property wherever the value is read, not only at a catch site.
 */
class NoSuchElementMessageReader {
    public static function describe(error:NoSuchElementFaultException):String {
        return error.message;
    }
}