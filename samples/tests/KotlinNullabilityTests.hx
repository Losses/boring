package tests;

import std.SortedMap;
import std.Test;

class KotlinNullabilityOps {
    #if kotlin_output
    public static function defaulted(?value:Int = 17):Int {
        return value;
    }

    public static function receiverLabel(value:Null<KotlinNullableReceiver>):Null<String> {
        return value.label();
    }
    #else
    public static function defaulted(value:Int):Int {
        return value;
    }

    public static function receiverLabel(value:KotlinNullableReceiver):String {
        return value.label();
    }
    #end
}

class KotlinNullableReceiver {
    public function new() {}

    public function label():String {
        return "present";
    }
}

/**
 * A slot whose element parameter is the bare class type parameter. Its element
 * nullability is visible only through the type arguments the receiver applies,
 * never in the declared signature.
 */
class KotlinNullableSlot<T> {
    public var stored:Int;

    var value:T;

    public function new(initial:T) {
        stored = 0;
        value = initial;
    }

    public function accept(next:T):Void {
        stored++;
        value = next;
    }

    public function peek():T {
        return value;
    }
}

class KotlinNullableProbe {
    public static function present():Null<KotlinNullableReceiver> {
        return new KotlinNullableReceiver();
    }

    public static function absent():Null<KotlinNullableReceiver> {
        return null;
    }

    public static function presentText():Null<String> {
        return "x";
    }

    public static function absentText():Null<String> {
        return null;
    }
}

class KotlinNullabilityTests {
    @:test("optional parameters emit a native default")
    public static function testOptionalDefault():Void {
        #if kotlin_output
        Test.equals(17, KotlinNullabilityOps.defaulted());
        #end
        Test.equals(23, KotlinNullabilityOps.defaulted(23));
    }

    @:test("nullable receiver calls preserve present values")
    public static function testNullableReceiver():Void {
        Test.equals("present", KotlinNullabilityOps.receiverLabel(new KotlinNullableReceiver()));
        #if kotlin_output
        Test.equals(null, KotlinNullabilityOps.receiverLabel(null));
        #end
    }

    @:test("generic receiver type arguments decide parameter nullability")
    public static function testGenericReceiverNullableParam():Void {
        final slot:KotlinNullableSlot<Null<KotlinNullableReceiver>> = new KotlinNullableSlot(KotlinNullableProbe.present());
        slot.accept(KotlinNullableProbe.present());
        Test.equals(1, slot.stored, "the present value was accepted");
        final present = slot.peek();
        Test.equals(false, present == null, "the present value round-trips");
        Test.equals("present", present == null ? "missing" : present.label());

        slot.accept(KotlinNullableProbe.absent());
        Test.equals(2, slot.stored, "the absent value was accepted");
        final absent = slot.peek();
        Test.equals(true, absent == null, "the stored null round-trips");
    }

    @:test("a nullable value type argument keeps sorted map nulls storable")
    public static function testSortedMapNullableValue():Void {
        final builder:SortedMapBuilder<Int, Null<String>> = SortedMap.builder();
        builder.put(1, KotlinNullableProbe.presentText());
        builder.put(2, KotlinNullableProbe.absentText());
        final map = builder.build();
        Test.equals(2, map.size(), "both entries were stored");
        Test.equals("x", map.get(1), "the present value round-trips");
        final absent = map.get(2);
        Test.equals(true, absent == null, "the null value round-trips");
        final stored = map.valueAt(1);
        Test.equals(true, stored == null, "the stored entry keeps its null value");
    }
}
