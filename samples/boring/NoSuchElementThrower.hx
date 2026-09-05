package boring;

/**
 * Raises the catch-only exception. The thrower keeps the exception type
 * referenced from source, so the emission gap it targets is whether a
 * module-listed class that only a catch names survives after its thrower
 * is inlined away.
 */
class NoSuchElementThrower {
    public static function missing():Int {
        throw new NoSuchElementFaultException(NoSuchElementFault.Missing);
        return 0;
    }
}