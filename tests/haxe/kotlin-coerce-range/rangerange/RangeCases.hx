package rangerange;

/**
    RangeBound coercion probe for P2.2.

    loopBound extracts the upper bound of a `for (i in 0 ... bound)` loop.
    When the bound renders nullable -- a nullable array field, or a function
    returning Null<Int> -- the emitted endpoint is Int? unless the emitter
    hardens it with !!; Kotlin rejects a nullable range endpoint with a
    type mismatch (the endpoint must be Int, not Int?).

    sumFieldBound reads the items field bound (items?.size!!), and
    sumCallBound reads the limit() call bound (limit()!!). Both loop bodies
    touch only the index, so the nullable array is never indexed (a
    different coercion question) and no runtime library is required.
**/
class RangeCases {
    public var items:Null<Array<Int>>;

    public function new() {
        items = null;
    }

    /** Nullable array field bound: emits items?.size!!. */
    public function sumFieldBound():Int {
        var total = 0;
        for (i in 0...items.length)
            total += i;
        return total;
    }

    /** Nullable Null<Int> function bound: emits limit()!!. */
    public function limit():Null<Int> {
        return null;
    }

    public function sumCallBound():Int {
        var total = 0;
        for (i in 0...limit())
            total += i;
        return total;
    }
}
