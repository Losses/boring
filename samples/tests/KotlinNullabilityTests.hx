package tests;

import std.Test;
import std.SortedMap;

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

class KotlinNestedNullReturnOps {
    public static function anonymousLookup(key:Int):String {
        final lookup = function(k:Int):Null<String> {
            if (k == 0)
                return null;
            return "hit";
        };
        final value = lookup(key);
        if (value == null)
            return "none";
        return value;
    }

    static function applyLookup(fn:Int->Null<String>, key:Int):String {
        final value = fn(key);
        if (value == null)
            return "none";
        return value;
    }

    public static function appliedLookup(key:Int):String {
        return applyLookup(function(k:Int):Null<String> {
            if (k == 0)
                return null;
            return "hit";
        }, key);
    }

    public static function namedLookup(key:Int):String {
        function lookup(k:Int):Null<String> {
            if (k == 0)
                return null;
            return "hit";
        }
        final value = lookup(key);
        if (value == null)
            return "none";
        return value;
    }
}

#if (kotlin_output || ts_output)
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

#end

class KotlinNullableReceiver {
    public function new() {}

    public function label():String {
        return "present";
    }
}

class KotlinNullGuardHolder {
    public var flag:Null<String>;
    public var count:Null<Int>;

    public function new(flag:Null<String>, count:Null<Int>) {
        this.flag = flag;
        this.count = count;
    }
}

class KotlinNullGuardBool {
    public final value:Bool;

    public function new(value:Bool) {
        this.value = value;
    }
}

/**
    A comparison over a nullable receiver renders with a safe call
    (`holder?.flag`). That text lands at a non-null `Bool` boundary, where the
    hardened argument used to append an elvis with no parentheses:
    `holder?.flag != null ?: throw ...` parses as
    `holder?.flag != (null ?: throw ...)` and throws unconditionally.
    (HardenAppendAtomicity)
**/
class KotlinNullGuardArgOps {
    public static function present():Null<KotlinNullGuardHolder> {
        return new KotlinNullGuardHolder("flag", 3);
    }

    public static function absent():Null<KotlinNullGuardHolder> {
        return null;
    }

    /** A present receiver whose nullable properties are themselves null: the
        comparison stays valid in every target, so both the Kotlin and the TS
        loop can assert the same verdict. */
    public static function nullFlag():Null<KotlinNullGuardHolder> {
        return new KotlinNullGuardHolder(null, null);
    }

    public static function acceptsFlag(flag:Bool):Bool {
        return flag;
    }

    public static function flagPresent(holder:Null<KotlinNullGuardHolder>):Bool {
        return acceptsFlag(holder.flag != null);
    }

    public static function countIsThree(holder:Null<KotlinNullGuardHolder>):Bool {
        return acceptsFlag(holder.count == 3);
    }

    public static function flagPresentCtor(holder:Null<KotlinNullGuardHolder>):Bool {
        final wrapped = new KotlinNullGuardBool(holder.flag != null);
        return wrapped.value;
    }

    public static function flagPresenceList(holder:Null<KotlinNullGuardHolder>):Array<Bool> {
        final flags:Array<Bool> = [holder.flag != null];
        return flags;
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

    @:test("anonymous lambda keeps a Null return")
    public static function testAnonymousNullableLambda():Void {
        Test.equals("none", KotlinNestedNullReturnOps.anonymousLookup(0));
        Test.equals("hit", KotlinNestedNullReturnOps.anonymousLookup(1));
    }

    @:test("lambda argument keeps a Null return")
    public static function testNullableLambdaArgument():Void {
        Test.equals("none", KotlinNestedNullReturnOps.appliedLookup(0));
        Test.equals("hit", KotlinNestedNullReturnOps.appliedLookup(1));
    }

    @:test("named local function keeps a Null return")
    public static function testNamedNullableLocalFunction():Void {
        Test.equals("none", KotlinNestedNullReturnOps.namedLookup(0));
        Test.equals("hit", KotlinNestedNullReturnOps.namedLookup(1));
    }
    @:test("generic receiver type arguments decide parameter nullability")
    public static function testGenericReceiverNullableParam():Void {
        #if (kotlin_output || ts_output)
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
        #end
    }

    @:test("a nullable receiver comparison keeps its value at a Bool argument")
    public static function testNullableComparisonArgument():Void {
        Test.equals(true, KotlinNullGuardArgOps.flagPresent(KotlinNullGuardArgOps.present()),
            "the guarded property reads present");
        Test.equals(false, KotlinNullGuardArgOps.flagPresent(KotlinNullGuardArgOps.nullFlag()),
            "a null property keeps the guard false");
        Test.equals(true, KotlinNullGuardArgOps.countIsThree(KotlinNullGuardArgOps.present()),
            "the property equals the constant");
        Test.equals(false, KotlinNullGuardArgOps.countIsThree(KotlinNullGuardArgOps.nullFlag()),
            "a null property never equals the constant");
        #if kotlin_output
        // Only Kotlin models a Null<T> receiver (every other target reads the
        // receiver through a plain dot), so the null-receiver verdict is
        // asserted here alone.
        Test.equals(false, KotlinNullGuardArgOps.flagPresent(KotlinNullGuardArgOps.absent()),
            "a null receiver keeps the guard false");
        Test.equals(false, KotlinNullGuardArgOps.countIsThree(KotlinNullGuardArgOps.absent()),
            "a null receiver never equals the constant");
        #end
    }

    @:test("a nullable receiver comparison survives ctor and array element boundaries")
    public static function testNullableComparisonHardening():Void {
        Test.equals(true, KotlinNullGuardArgOps.flagPresentCtor(KotlinNullGuardArgOps.present()));
        Test.equals(false, KotlinNullGuardArgOps.flagPresentCtor(KotlinNullGuardArgOps.nullFlag()));
        final presentFlags = KotlinNullGuardArgOps.flagPresenceList(KotlinNullGuardArgOps.present());
        final absentFlags = KotlinNullGuardArgOps.flagPresenceList(KotlinNullGuardArgOps.nullFlag());
        Test.equals(1, presentFlags.length);
        Test.equals(1, absentFlags.length);
        Test.equals(true, presentFlags[0]);
        Test.equals(false, absentFlags[0]);
    }

    @:test("a nullable value type argument keeps sorted map nulls storable")
    public static function testSortedMapNullableValue():Void {
        #if (kotlin_output || ts_output)
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
        #end
    }
}
