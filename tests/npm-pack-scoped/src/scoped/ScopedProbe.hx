package scoped;

/**
 * The one module of the scoped npm fixture: it gives the packed tree a
 * module and an exports entry so pack has a package to write.
 */
class ScopedProbe {
    /** A fixed label, so the module carries a body. */
    public static function label():String {
        return "scoped-probe";
    }
}
