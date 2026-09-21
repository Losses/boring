package tests;

import std.Test;

#if (kotlin_output || ts_output)
import boring.ArraySliceOps;
#end

/**
    The Haxe contract bounds an Array slice at both ends: a negative position
    counts from the end of the array, a position past the end clamps to the
    length, and a bound that reaches the other bound or passes it yields the
    empty array. The TypeScript target reaches the JavaScript prototype slice,
    which applies those bounds, and the Kotlin target has to apply them before
    it calls the range overload, which throws on an end past the list.
    (ArraySliceClamping)

    The Haxe contract bounds Array.splice before it removes anything: a
    negative length or a position past the length returns the empty array and
    leaves the array unchanged, a negative position counts from the end and
    stops at the first element, and a length that reaches past the end removes
    only the tail. The JavaScript prototype splice already reads a call that
    way, so the TypeScript target carries the contract through the native call
    while the Kotlin target clamps the position and trims the count before it
    reaches the range overload, which throws on a bound outside the list.
    Both targets must agree on every case below. (ArraySpliceClamping)
**/
class ArraySliceTests {
    /**
        A fixed end of 20 on arrays of length 0, 1, and 5. The engine tree
        carried this call on an empty failure array and the Kotlin range
        overload threw IndexOutOfBoundsException from subList.
    **/
    @:test("an end past the length returns the elements the array carries")
    public static function testEndPastLength():Void {
        #if (kotlin_output || ts_output)
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
        #if (kotlin_output || ts_output)
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
        #if (kotlin_output || ts_output)
        Test.equals("", ArraySliceOps.sliceText(0, -3, 2));
        Test.equals("1", ArraySliceOps.sliceText(1, -3, 2));
        Test.equals("", ArraySliceOps.sliceText(5, -3, 2));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        The one-bound call carries an omitted end, which Haxe reads as the
        length of the array. The TypeScript target used to render that omitted
        end as a null second argument, which the JavaScript prototype reads as
        an end of zero, so the two targets disagreed on every case here and
        this case only ran on Kotlin. The TypeScript lowering now drops the
        omitted end and both targets carry the suffix call. (ArraySliceClamping)
    **/
    @:test("an omitted end reaches the length of the array")
    public static function testOmittedEnd():Void {
        #if (kotlin_output || ts_output)
        Test.equals("3,4,5", ArraySliceOps.fromText(5, 2));
        Test.equals("4,5", ArraySliceOps.fromText(5, -2));
        Test.equals("", ArraySliceOps.fromText(5, 9));
        Test.equals("", ArraySliceOps.fromText(0, 0));
        Test.equals("1", ArraySliceOps.fromText(1, -1));
        Test.equals("", ArraySliceOps.fromText(1, 1));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        A negative length removes nothing and leaves the array alone at every
        length, including when the position is negative or past the length as
        well, because the length is refused before the position is read. The
        Kotlin range overload threw on the negative length.
        (ArraySpliceClamping)
    **/
    @:test("a negative length removes nothing and leaves the array alone")
    public static function testSpliceNegativeLength():Void {
        #if (kotlin_output || ts_output)
        Test.equals("|", ArraySliceOps.spliceText(0, 0, -1));
        Test.equals("|1", ArraySliceOps.spliceText(1, 0, -1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 2, -1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, -3, -1));
        Test.equals("|1,2,3,4,5", ArraySliceOps.spliceText(5, 20, -1));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        A position past the length removes nothing and leaves the array alone,
        at every length and for every length; a position that lands exactly on
        the length is not past it and also removes nothing, because no element
        remains after it. (ArraySpliceClamping)
    **/
    @:test("a position past the length removes nothing")
    public static function testSplicePositionPastLength():Void {
        #if (kotlin_output || ts_output)
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

    /**
        A negative position counts from the end of the array by the same rule
        the slice uses, and a position that stays before the first element
        reads as 0 rather than as a refusal: the fold clamps to 0 and the
        count then removes from the start. Kotlin reached the range overload
        with the raw negative index, and Dart and Swift reach their own range
        overload with it.
    **/
    @:test("a negative position counts from the end of the array")
    public static function testSpliceNegativePosition():Void {
        #if (kotlin_output || ts_output)
        Test.equals("|", ArraySliceOps.spliceText(0, -1, 2));
        Test.equals("|", ArraySliceOps.spliceText(0, -9, 1));
        Test.equals("1|", ArraySliceOps.spliceText(1, -1, 1));
        Test.equals("1|", ArraySliceOps.spliceText(1, -3, 1));
        Test.equals("1|", ArraySliceOps.spliceText(1, -9, 2));
        Test.equals("5|1,2,3,4", ArraySliceOps.spliceText(5, -1, 2));
        Test.equals("3|1,2,4,5", ArraySliceOps.spliceText(5, -3, 1));
        Test.equals("3,4|1,2,5", ArraySliceOps.spliceText(5, -3, 2));
        Test.equals("1|2,3,4,5", ArraySliceOps.spliceText(5, -9, 1));
        Test.equals("1,2|3,4,5", ArraySliceOps.spliceText(5, -9, 2));
        #else
        Test.equals(true, true);
        #end
    }

    /**
        A length that reaches past the end removes only the elements that
        remain after the position and leaves the array shorter by that tail;
        the returned sub-array and the array that remains always hold every
        element of the original between them. (ArraySpliceClamping)
    **/
    @:test("a length past the end removes only the tail")
    public static function testSpliceLengthPastEnd():Void {
        #if (kotlin_output || ts_output)
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

    /** Both refusals on a splice through an array local that declares a null
        start and holds a value by the time the call runs. */
    @:test("a splice on a null-initialized array local clamps as well")
    public static function testNullInitSplice():Void {
        #if (kotlin_output || ts_output)
        Test.equals("|", ArraySliceOps.nullInitSpliceText(0, 0, 20));
        Test.equals("|1,2,3,4,5", ArraySliceOps.nullInitSpliceText(5, 6, -1));
        Test.equals("1|2,3,4,5", ArraySliceOps.nullInitSpliceText(5, 0, 1));
        #else
        Test.equals(true, true);
        #end
    }

    /** A slice through a nullable receiver keeps the null result of an
        absent array and never reaches the range overload. */
    @:test("a slice through an absent array returns null")
    public static function testNullableReceiver():Void {
        #if (kotlin_output || ts_output)
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
        #if (kotlin_output || ts_output)
        Test.equals("", ArraySliceOps.nullInitText(0));
        Test.equals("1,2,3,4,5", ArraySliceOps.nullInitText(5));
        #else
        Test.equals(true, true);
        #end
    }

    /** The literal shape the engine tree carried, on an empty array. */
    @:test("a fixed end of 20 on an empty array returns an empty slice")
    public static function testEmptyToTwenty():Void {
        #if (kotlin_output || ts_output)
        Test.equals("", ArraySliceOps.emptyToTwentyText());
        Test.equals(0, ArraySliceOps.emptyToTwentySize());
        #else
        Test.equals(true, true);
        #end
    }
}
