package std;

/**
 * Two-field range abstract (docs/specs/stdlib/09-inline-arithmetic-helpers.md).
 * Inlines contains() using Arithmetic.within; erases to structure { start:Int, end:Int }.
 */
abstract IntRange({start:Int, end:Int}) from {start:Int, end:Int} to {start:Int, end:Int} {
    public inline function contains(value:Int):Bool {
        return Arithmetic.within(value, this.start, this.end);
    }
}
