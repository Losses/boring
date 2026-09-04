package std;

/**
 * Static inline arithmetic and range-check helpers (docs/specs/stdlib/09-inline-arithmetic-helpers.md).
 * Inlined at every call site by the Haxe compiler; no runtime module exists.
 */
class Arithmetic {
    public static inline function within<T:Float>(v:T, low:T, high:T):Bool {
        return v >= low && v <= high;
    }

    public static inline function coerceAtLeast<T:Float>(v:T, floor:T):T {
        return v < floor ? floor : v;
    }

    public static inline function coerceAtMost<T:Float>(v:T, ceiling:T):T {
        return v > ceiling ? ceiling : v;
    }

    public static inline function coerceIn<T:Float>(value:T, low:T, high:T):T {
        return coerceAtMost(coerceAtLeast(value, low), high);
    }
}
