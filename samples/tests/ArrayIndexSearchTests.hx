package tests;

import std.Test;

#if (kotlin_output || ts_output)
import boring.ArrayIndexSearchOps;
#end

/**
    The four shapes of a Haxe `Array` index search. Every shape reads the
    same probe array, whose needle `7` sits at index 1 and index 4, so a
    shape that loses its start index reports a different occurrence.
    (ArrayIndexSearch)
**/
class ArrayIndexSearchTests {
    @:test("an element-only array search reads the platform overload")
    public static function testElementOnly():Void {
        #if (kotlin_output || ts_output)
        final values = ArrayIndexSearchOps.values();
        Test.equals(1, ArrayIndexSearchOps.indexOfElement(values, 7));
        Test.equals(4, ArrayIndexSearchOps.lastIndexOfElement(values, 7));
        // A miss reports -1 in both directions.
        Test.equals(-1, ArrayIndexSearchOps.indexOfElement(values, 8));
        Test.equals(-1, ArrayIndexSearchOps.lastIndexOfElement(values, 8));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("an array indexOf keeps its start index")
    public static function testIndexOfFrom():Void {
        #if (kotlin_output || ts_output)
        final values = ArrayIndexSearchOps.values();
        // The start index is inclusive, and it is reached from both sides:
        // index 1 still matches, index 2 resumes past the first occurrence.
        Test.equals(1, ArrayIndexSearchOps.indexOfFrom(values, 7, 0));
        Test.equals(1, ArrayIndexSearchOps.indexOfFrom(values, 7, 1));
        Test.equals(4, ArrayIndexSearchOps.indexOfFrom(values, 7, 2));
        // The last element index holds no needle, so the search reports a miss.
        Test.equals(-1, ArrayIndexSearchOps.indexOfFrom(values, 7, 5));
        // A start index at or past the length reports a miss.
        Test.equals(-1, ArrayIndexSearchOps.indexOfFrom(values, 7, 6));
        Test.equals(-1, ArrayIndexSearchOps.indexOfFrom(values, 7, 100));
        // A negative start index counts from the end, so -3 starts at index 3
        // past the first occurrence, and -100 reaches before the start and
        // searches the whole array.
        Test.equals(4, ArrayIndexSearchOps.indexOfFrom(values, 7, -3));
        Test.equals(1, ArrayIndexSearchOps.indexOfFrom(values, 7, -100));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("an array lastIndexOf searches towards index 0 from its start index")
    public static function testLastIndexOfFrom():Void {
        #if (kotlin_output || ts_output)
        final values = ArrayIndexSearchOps.values();
        // The start index is the beginning of a backwards search, so the
        // occurrence sitting exactly at it still matches.
        Test.equals(4, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 4));
        Test.equals(1, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 3));
        Test.equals(1, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 1));
        // Index 0 holds the value 5, so the backwards search misses there.
        Test.equals(-1, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 0));
        // A start index at the last element and past the end both search the
        // whole array, which is what the omitted start index does.
        Test.equals(4, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 5));
        Test.equals(4, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 100));
        // A negative start index counts from the end; one that reaches before
        // the start reports a miss.
        Test.equals(4, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, -2));
        Test.equals(-1, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, -100));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("an empty array reports a miss in every shape")
    public static function testEmpty():Void {
        #if (kotlin_output || ts_output)
        final values = ArrayIndexSearchOps.empty();
        Test.equals(-1, ArrayIndexSearchOps.indexOfElement(values, 7));
        Test.equals(-1, ArrayIndexSearchOps.indexOfFrom(values, 7, 0));
        Test.equals(-1, ArrayIndexSearchOps.lastIndexOfElement(values, 7));
        Test.equals(-1, ArrayIndexSearchOps.lastIndexOfFrom(values, 7, 0));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a nullable array receiver keeps its start index")
    public static function testNullableReceiver():Void {
        #if (kotlin_output || ts_output)
        final values = ArrayIndexSearchOps.values();
        Test.equals(1, ArrayIndexSearchOps.indexOfFromNullable(values, 7, 0));
        Test.equals(4, ArrayIndexSearchOps.lastIndexOfFromNullable(values, 7, 5));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("an array search compares a String element by value")
    public static function testStringElement():Void {
        #if (kotlin_output || ts_output)
        final words = ["alpha", "beta", "gamma", "beta"];
        Test.equals(1, ArrayIndexSearchOps.indexOfString(words, "beta", 0));
        Test.equals(3, ArrayIndexSearchOps.indexOfString(words, "beta", 2));
        Test.equals(-1, ArrayIndexSearchOps.indexOfString(words, "beta", 4));
        Test.equals(3, ArrayIndexSearchOps.lastIndexOfString(words, "beta", 4));
        Test.equals(1, ArrayIndexSearchOps.lastIndexOfString(words, "beta", 2));
        // A String lastIndexOf with the start index omitted scans from the
        // last unit, so the last "a" of the text is index 15 and a scan that
        // started at index 0 would report the first one instead.
        Test.equals(15, ArrayIndexSearchOps.lastIndexOfTextEnd("alpha beta gamma", "a"));
        Test.equals(-1, ArrayIndexSearchOps.lastIndexOfTextEnd("alpha beta gamma", "z"));
        #else
        Test.equals(true, true);
        #end
    }
}
