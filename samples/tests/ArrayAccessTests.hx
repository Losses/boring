package tests;

import boring.ArrayAccessOps;
import std.Test;

class ArrayAccessTests {
    @:test("split results support written array access")
    public static function testWriteSplit():Void {
        Test.equals("x", ArrayAccessOps.writeSplit("a,b"));
    }

    @:test("split results support read array access")
    public static function testReadSplit():Void {
        Test.equals("a", ArrayAccessOps.readSplit("a,b"));
    }



    @:test("composite StringBuf part can read its first character")
    public static function testCompositePart():Void {
        Test.equals(65, ArrayAccessOps.compositeStringBufPart("A"));
    }

    @:test("simple StringBuf part can read its first character")
    public static function testSimplePart():Void {
        Test.equals(65, ArrayAccessOps.simpleStringBufPart("A"));
    }

    /**
        Haxe grows an Array when an index write reaches past the end, so the
        Kotlin backend must grow its MutableList instead of throwing
        IndexOutOfBoundsException. (ArrayGrowthOnIndexWrite)
    **/
    @:test("an index write past the end grows a nullable-element array")
    public static function testGrowNullableSlots():Void {
        #if (kotlin_output || ts_output)
        final slots = ArrayAccessOps.growNullableSlots();
        Test.equals(4, slots.length);
        Test.equals(7, slots[3]);
        #if kotlin_output
        // The growth fills every skipped slot with the element type's
        // default value: null for a nullable element type, and the zero of
        // the value for a value element type, which is what the JVM array
        // Haxe itself grows stores. JavaScript leaves holes instead, so the
        // fill is asserted for the Kotlin target only.
        Test.equals(true, slots[0] == null);
        Test.equals(true, slots[1] == null);
        Test.equals(true, slots[2] == null);
        #end
        #end
    }

    @:test("an index write past the end grows a value-element array")
    public static function testGrowValueSlots():Void {
        #if (kotlin_output || ts_output)
        final slots = ArrayAccessOps.growValueSlots();
        Test.equals(3, slots.length);
        Test.equals(5, slots[2]);
        #if kotlin_output
        // A Kotlin value element type has no null to fill with, so the
        // growth fills its zero; JavaScript leaves holes, which is why the
        // fill is asserted for the Kotlin target only.
        Test.equals(true, slots[0] == 0);
        Test.equals(true, slots[1] == 0);
        #end
        #end
    }

    @:test("an index loop over an empty array field grows it")
    public static function testGrowFieldSlots():Void {
        #if (kotlin_output || ts_output)
        final slots = ArrayAccessOps.filledHolder(3);
        Test.equals(4, slots.length);
        Test.equals(0, slots[0]);
        Test.equals(30, slots[3]);
        #end
    }

    /**
        Haxe fills the skipped slots of a grown array with the element type's
        default value, and the Kotlin target spells that fill with the
        element type's own literal: a Double zero in a MutableList<Float> is
        a compile error, which is what the f32 engine tree hit.
        (ArrayGrowthOnIndexWrite)
    **/
    @:test("an index write past the end grows a float-element array")
    public static function testGrowFloatSlots():Void {
        #if (kotlin_output || ts_output)
        final slots = ArrayAccessOps.growFloatSlots();
        Test.equals(3, slots.length);
        Test.equals(1.5, slots[2]);
        #if kotlin_output
        // The fill literal has to match the element type, so the skipped
        // slots read back as the Float zero. JavaScript leaves holes, which
        // is why the fill is asserted for the Kotlin target only.
        Test.equals(true, slots[0] == 0.0);
        Test.equals(true, slots[1] == 0.0);
        #end
        #end
    }

    @:test("an index loop over an empty float array field grows it")
    public static function testGrowFloatFieldSlots():Void {
        #if (kotlin_output || ts_output)
        final slots = ArrayAccessOps.filledFloatHolder(2);
        Test.equals(3, slots.length);
        Test.equals(3.0, slots[2]);
        Test.equals(0.0, slots[0]);
        #end
    }

    @:test("writes inside an array keep their slots")
    public static function testWriteInsideSlots():Void {
        #if (kotlin_output || ts_output)
        final slots = ArrayAccessOps.writeInsideSlots();
        Test.equals(5, slots.length);
        Test.equals(20, slots[1]);
        Test.equals(40, slots[3]);
        Test.equals(50, slots[4]);
        #end
    }
}
