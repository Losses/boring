package boring;

/**
    Haxe bounds an Array slice at both ends before it copies. A negative
    position or end counts from the end of the array, a bound past the end
    clamps to the length, and an end that reaches the position or passes it
    yields the empty array. The Kotlin platform slice takes a half-open range
    and throws when the range end reaches past the list, so the backend clamps
    both bounds before it calls that overload. (ArraySliceClamping)
**/
class ArraySliceOps {
    /** An ascending array of `count` values, starting at 1. */
    public static function values(count:Int):Array<Int> {
        final out:Array<Int> = [];
        var i = 0;
        while (i < count) {
            out.push(i + 1);
            i++;
        }
        return out;
    }

    /** The comma separated text of the two-bound slice of a `count` array. */
    public static function sliceText(count:Int, from:Int, to:Int):String {
        return values(count).slice(from, to).join(",");
    }

    /**
        The one-bound call carries an omitted end, which Haxe reads as the
        length of the array.
    **/
    public static function fromText(count:Int, from:Int):String {
        return values(count).slice(from).join(",");
    }

    /**
        `"<removed>|<array after>"` of `values(count).splice(pos, len)`, so
        one call records both halves of the operation: the sub-array the call
        returns and the array it leaves behind. Haxe bounds the call before it
        removes anything: a negative length or a position past the length
        removes nothing and leaves the array alone, a negative position counts
        from the end and stops at the first element, and a length that reaches
        past the end removes only the tail. (ArraySpliceClamping)
    **/
    public static function spliceText(count:Int, pos:Int, len:Int):String {
        final values = ArraySliceOps.values(count);
        final removed = values.splice(pos, len);
        return removed.join(",") + "|" + values.join(",");
    }

    /**
        The text of `values(count)` after `insert(pos, 99)`, which records
        the offset the clamped position chose. Haxe bounds the position before
        the array sees it: a negative position counts from the end and stops at
        the first element, and a position past the length clamps to the length.
        (ArrayInsertClamping)
    **/
    public static function insertText(count:Int, pos:Int):String {
        final values = ArraySliceOps.values(count);
        values.insert(pos, 99);
        return values.join(",");
    }

    /** A slice through a nullable receiver, which the backend lowers through
        the same clamping and keeps the null result of an absent array. */
    public static function nullableText(values:Null<Array<Int>>, from:Int, to:Int):String {
        final sliced = values?.slice(from, to);
        return sliced == null ? "none" : sliced.join(",");
    }

    /**
        The engine shape of an array local that declares a null start and holds
        a value by the time the slice runs.
    **/
    public static function nullInitText(count:Int):String {
        var values:Array<Int> = null;
        values = ArraySliceOps.values(count);
        return values.slice(0, 20).join(",");
    }

    /**
        The shape the engine tree carried: a fixed end on an array that the
        case filled with no element, which is the call that threw
        IndexOutOfBoundsException from the Kotlin range slice.
    **/
    public static function emptyToTwentyText():String {
        final failures:Array<String> = [];
        return failures.slice(0, 20).join(",");
    }

    /** The length of the slice of an empty array to a fixed end of 20. */
    public static function emptyToTwentySize():Int {
        final failures:Array<String> = [];
        return failures.slice(0, 20).length;
    }
}
