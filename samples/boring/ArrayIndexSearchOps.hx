package boring;

#if (kotlin_output || ts_output)
/**
    The four shapes of a Haxe `Array` index search: `indexOf(x)`,
    `indexOf(x, from)`, `lastIndexOf(x)`, and `lastIndexOf(x, from)`.
    The platform list type carries an element-only `indexOf` and
    `lastIndexOf`, so a start index has no overload to call and the
    search runs on the sublist that index bounds. (ArrayIndexSearch)
**/
class ArrayIndexSearchOps {
    /**
        A probe array whose needle `7` sits at index 1 and index 4: the
        two occurrences separate a search that starts at the first
        occurrence from one that starts after it.
    **/
    public static function values():Array<Int> {
        return [5, 7, 9, 11, 7, 13];
    }

    /** `indexOf(x)`: the first occurrence, searched from index 0. **/
    public static function indexOfElement(values:Array<Int>, x:Int):Int {
        return values.indexOf(x);
    }

    /** `indexOf(x, from)`: the first occurrence at or after `from`. **/
    public static function indexOfFrom(values:Array<Int>, x:Int, from:Int):Int {
        return values.indexOf(x, from);
    }

    /**
        `lastIndexOf(x)`: the last occurrence, searched from the last
        element index. A search that starts at index 0 reads the element at
        index 0 only, so the omitted start index is part of the result.
    **/
    public static function lastIndexOfElement(values:Array<Int>, x:Int):Int {
        return values.lastIndexOf(x);
    }

    /**
        `lastIndexOf(x, from)`: the last occurrence at or before `from`,
        searching towards index 0.
    **/
    public static function lastIndexOfFrom(values:Array<Int>, x:Int, from:Int):Int {
        return values.lastIndexOf(x, from);
    }

    /** The forward shape over a String element, which compares by value. **/
    public static function indexOfString(values:Array<String>, x:String, from:Int):Int {
        return values.indexOf(x, from);
    }

    /** The backwards String shape, which searches towards index 0. **/
    public static function lastIndexOfString(values:Array<String>, x:String, from:Int):Int {
        return values.lastIndexOf(x, from);
    }

    /**
        `String.lastIndexOf(x)` with the start index omitted: the scan
        starts at the last unit index, so the platform call takes the
        element alone. A literal null start index would be coerced to 0 and
        report the first occurrence instead.
    **/
    public static function lastIndexOfTextEnd(text:String, x:String):Int {
        return text.lastIndexOf(x);
    }

    /**
        A nullable receiver with no dominating guard: the forward search
        renders through the null extraction the emitter chooses for that
        receiver, so the start index survives on both access shapes.
    **/
    public static function indexOfFromNullable(values:Null<Array<Int>>, x:Int, from:Int):Int {
        return values.indexOf(x, from);
    }

    /** The backwards search on the same nullable receiver. **/
    public static function lastIndexOfFromNullable(values:Null<Array<Int>>, x:Int, from:Int):Int {
        return values.lastIndexOf(x, from);
    }

    /** An empty receiver for the miss shapes. **/
    public static function empty():Array<Int> {
        return [];
    }
}
#else
class ArrayIndexSearchOps {}
#end
