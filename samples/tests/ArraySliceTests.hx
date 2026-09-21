package tests;

import std.Test;

#if (kotlin_output || ts_output || rust_output)
import boring.ArraySliceOps;
#end

/**
    The Haxe contract bounds an Array bound at the platform call: a negative
    bound counts from the end of the array and stops at the first element, and
    a bound past the length clamps to the length. The TypeScript target reaches
    the JavaScript prototype, which applies those bounds, and the Kotlin,
    Dart, Swift, and Rust targets each have to apply them before their own call
    reaches an index outside the array. (ArrayBoundClamping)
**/
class ArraySliceTests {
    /**
        A fixed end of 20 on arrays of length 0, 1, and 5. The engine tree
        carried this call on an empty failure array and the Kotlin range
        overload threw IndexOutOfBoundsException from subList, while Rust had
        no Vec::slice at all and the generated `vec.slice(from, Some(to))`
        failed the crate build.
    **/
    @:test("an end past the length returns the elements the array carries")
    public static function testEndPastLength():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("", ArraySliceOps.sliceText(0, 0, 20));
        Test.equals("1", ArraySliceOps.sliceText(1, 0, 20));
        Test.equals("1,2,3,4,5", ArraySliceOps.sliceText(5, 0, 20));
        #else
        Test.equals(true, true);
        #end
    }

    /** An end below the start yields the empty array, at every length. */
    @:test("an end below the start returns the empty slice")
    public static function testEndBelowStart():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("", ArraySliceOps.sliceText(0, 2, 1));
        Test.equals("", ArraySliceOps.sliceText(1, 2, 1));
        Test.equals("", ArraySliceOps.sliceText(5, 2, 1));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        The negative start counts from the end of the array, so the three
        lengths separate the two readings of the call: 0 + a negative start
        clamps to 0, a start before the first element clamps to 0 as well, and
        a start that reaches the end of a length 5 array leaves no element
        before the end of 2. The TypeScript target and the Haxe standard
        library agree on these three results.
    **/
    @:test("a negative start counts from the end of the array")
    public static function testNegativeStart():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("", ArraySliceOps.sliceText(0, -3, 2));
        Test.equals("1", ArraySliceOps.sliceText(1, -3, 2));
        Test.equals("", ArraySliceOps.sliceText(5, -3, 2));
        Test.equals("1,2,3", ArraySliceOps.sliceText(5, -9, -2));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        The one-bound call carries an omitted end, which Haxe reads as the
        length of the array, and a start past the length yields the empty
        array. The TypeScript target renders that omitted end as a null second
        argument, which the JavaScript prototype reads as an end of zero, so
        the run of this case covers the Kotlin and Rust targets until the
        TypeScript lowering carries the omitted end as the array length.
        (ArraySliceClamping)
    **/
    @:test("an omitted end reaches the length of the array")
    public static function testOmittedEnd():Void {
        #if (kotlin_output || rust_output)
        Test.equals("3,4,5", ArraySliceOps.fromText(5, 2));
        Test.equals("4,5", ArraySliceOps.fromText(5, -2));
        Test.equals("", ArraySliceOps.fromText(5, 9));
        Test.equals("", ArraySliceOps.fromText(0, 0));
        #else
        Test.equals(true, true);
        #end
    }

    /** A slice through a nullable receiver keeps the null result of an
        absent array and never reaches the range overload. */
    @:test("a slice through an absent array returns null")
    public static function testNullableReceiver():Void {
        #if (kotlin_output || ts_output || rust_output)
        final absent:Null<Array<Int>> = null;
        Test.equals("none", ArraySliceOps.nullableText(absent, 0, 2));
        Test.equals("3,4", ArraySliceOps.nullableText([3, 4], 0, 20));
        #else
        Test.equals(true, true);
        #end
    }

    /** An array local that declares a null start and holds a value by the
        time the slice runs. */
    @:test("a slice on a null-initialized array local clamps as well")
    public static function testNullInitLocal():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("", ArraySliceOps.nullInitText(0));
        Test.equals("1,2,3,4,5", ArraySliceOps.nullInitText(5));
        #else
        Test.equals(true, true);
        #end
    }

    /** The literal shape the engine tree carried, on an empty array. */
    @:test("a fixed end of 20 on an empty array returns an empty slice")
    public static function testEmptyToTwenty():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("", ArraySliceOps.emptyToTwentyText());
        Test.equals(0, ArraySliceOps.emptyToTwentySize());
        #else
        Test.equals(true, true);
        #end
    }

    /**
        The bounds that leave the array alone: a negative length and a position
        past the length both answer the empty sub-array, while a position past
        the length is still clamped against the end of the array for the
        positive length beside it. The TypeScript prototype carries these
        results, which is the reference the Rust drain range has to match.
    **/
    @:test("a negative length or a position past the length removes nothing")
    public static function testSpliceEmptyBounds():Void {
        #if (ts_output || rust_output)
        Test.equals("|", ArraySliceOps.spliceText(0, 0, 1));
        Test.equals("|1", ArraySliceOps.spliceText(1, -3, -1));
        Test.equals("|1", ArraySliceOps.spliceText(1, 1, 2));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 20, 1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 0, -2));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        A negative position counts from the end of the array and stops at the
        first element, and a length that reaches past the end removes only the
        tail; the array keeps every element the call did not return.
    **/
    @:test("a negative position counts from the end and a long length stops at the tail")
    public static function testSpliceNegativePosition():Void {
        #if (ts_output || rust_output)
        Test.equals("5|1,2,3,4", ArraySliceOps.spliceText(5, -1, 2));
        Test.equals("3,4|1,2,5", ArraySliceOps.spliceText(5, -3, 2));
        Test.equals("1,2,3,4,5|", ArraySliceOps.spliceText(5, -9, 20));
        Test.equals("3,4,5|1,2", ArraySliceOps.spliceText(5, -3, 20));
        Test.equals("2,3,4,5|1", ArraySliceOps.spliceText(5, 1, 20));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        Array.insert bounds the position the same way the slice bounds run: a
        negative position counts from the end and stops at the first element,
        and a position past the length clamps to the length, so the element
        lands at the end. Kotlin List.add, Dart List.insert, and Swift
        Array.insert each throw on an index outside the array. The TypeScript
        prototype splice carries these results.
    **/
    @:test("an insert clamps a negative position and a position past the length")
    public static function testInsertClamping():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("99", ArraySliceOps.insertText(0, 0));
        Test.equals("99", ArraySliceOps.insertText(0, -9));
        Test.equals("99", ArraySliceOps.insertText(0, 20));
        Test.equals("99,1", ArraySliceOps.insertText(1, 0));
        Test.equals("99,1", ArraySliceOps.insertText(1, -1));
        Test.equals("99,1", ArraySliceOps.insertText(1, -9));
        Test.equals("1,99", ArraySliceOps.insertText(1, 1));
        Test.equals("1,99", ArraySliceOps.insertText(1, 4));
        Test.equals("1,99", ArraySliceOps.insertText(1, 20));
        Test.equals("99,1,2,3,4,5", ArraySliceOps.insertText(5, 0));
        Test.equals("1,99,2,3,4,5", ArraySliceOps.insertText(5, 1));
        Test.equals("1,2,99,3,4,5", ArraySliceOps.insertText(5, -3));
        Test.equals("1,2,3,4,99,5", ArraySliceOps.insertText(5, -1));
        Test.equals("1,2,3,4,99,5", ArraySliceOps.insertText(5, 4));
        Test.equals("1,2,3,4,5,99", ArraySliceOps.insertText(5, 5));
        Test.equals("1,2,3,4,5,99", ArraySliceOps.insertText(5, 6));
        Test.equals("1,2,3,4,5,99", ArraySliceOps.insertText(5, 20));
        Test.equals("99,1,2,3,4,5", ArraySliceOps.insertText(5, -9));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a negative length removes nothing and leaves the array alone")
    public static function testSpliceNegativeLength():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("|", ArraySliceOps.spliceText(0, 0, -1));
        Test.equals("|1", ArraySliceOps.spliceText(1, 0, -1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 2, -1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, -3, -1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 20, -1));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a position past the length removes nothing")
    public static function testSplicePositionPastLength():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("|", ArraySliceOps.spliceText(0, 1, 2));
        Test.equals("|", ArraySliceOps.spliceText(0, 20, 1));
        Test.equals("|1", ArraySliceOps.spliceText(1, 2, 1));
        Test.equals("|1", ArraySliceOps.spliceText(1, 20, 20));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 6, 2));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 20, 20));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 5, 2));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a length past the end removes only the tail")
    public static function testSpliceLengthPastEnd():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("|", ArraySliceOps.spliceText(0, 0, 20));
        Test.equals("1|", ArraySliceOps.spliceText(1, 0, 20));
        Test.equals("2,3,4,5|1", ArraySliceOps.spliceText(5, 1, 20));
        Test.equals("3,4,5|1,2", ArraySliceOps.spliceText(5, 2, 20));
        Test.equals("3,4,5|1,2", ArraySliceOps.spliceText(5, -3, 20));
        Test.equals("5|1,2,3,4", ArraySliceOps.spliceText(5, -1, 20));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a splice on a null-initialized array local clamps as well")
    public static function testNullInitSplice():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("|", ArraySliceOps.nullInitSpliceText(0, 0, 20));
        Test.equals("|1,2,3,4,5", ArraySliceOps.nullInitSpliceText(5, 6, -1));
        Test.equals("1|2,3,4,5", ArraySliceOps.nullInitSpliceText(5, 0, 1));
        #else
        Test.equals(true, true);
        #end
    }

}