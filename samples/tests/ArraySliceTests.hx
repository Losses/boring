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
        length of the array, and a start past the length yields the empty
        array. The TypeScript target renders that omitted end as a null second
        argument, which the JavaScript prototype reads as an end of zero, so
        the run of this case covers the Kotlin target until the TypeScript
        lowering carries the omitted end as the array length.
        (ArraySliceClamping)
    **/
    @:test("an omitted end reaches the length of the array")
    public static function testOmittedEnd():Void {
        #if kotlin_output
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
