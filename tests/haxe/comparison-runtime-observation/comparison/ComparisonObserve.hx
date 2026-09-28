package comparison;

import std.ReadOnlyArray;
import std.SortedMap;

enum SharedKeyKind {
    SharedFirst;
    SharedSecond;
}

/**
    Authored observation module for the comparison observation fixture. The four
    record declarations carry one key field each, so one generated comparator
    answers one case group of stdlib spec 16, and the four names stay distinct
    inside one module, which keeps every declaration identity unambiguous.

    The module states no ordering rule of its own. Every function builds sorted
    tables through std.SortedMap, the source operation that binds the resident
    comparator of its key type, and reports the table order it observes. The
    native harnesses under tests/haxe/comparison-runtime-observation/native call these
    functions and print the returned text; they hold no ordering decision.
**/
@:dataClass
class IntKey {
    public final value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}

@:dataClass
class ArrayKey {
    public final items:ReadOnlyArray<Int>;

    public function new(items:ReadOnlyArray<Int>) {
        this.items = items;
    }
}

@:dataClass
class NullableArrayKey {
    public final items:Null<ReadOnlyArray<Int>>;

    public function new(items:Null<ReadOnlyArray<Int>>) {
        this.items = items;
    }
}

@:dataClass
class NullableIntKey {
    public final value:Null<Int>;

    public function new(value:Null<Int>) {
        this.value = value;
    }
}

@:dataClass
class MixedSignArrayKey {
    public final items:ReadOnlyArray<Int>;

    public function new(items:ReadOnlyArray<Int>) {
        this.items = items;
    }
}

@:dataClass
class StringKey {
    public final text:String;

    public function new(text:String) {
        this.text = text;
    }
}

@:dataClass
class FirstSharedEnumKey {
    public final value:SharedKeyKind;

    public function new(value:SharedKeyKind) {
        this.value = value;
    }
}

@:dataClass
class SecondSharedEnumKey {
    public final value:SharedKeyKind;

    public function new(value:SharedKeyKind) {
        this.value = value;
    }
}

class ComparisonObserve {
    /**
        The Int field group: ordinary unequal operands, the same two values
        with the operands exchanged, and equal operands. The ordering has to
        follow the values, and the equal pair has to leave one table entry.
    **/
    public static function intOrdinary():String {
        return "unequal=" + intPair(new IntKey(1), new IntKey(2)) + "|swapped=" + intPair(new IntKey(2), new IntKey(1)) + "|equal="
            + intEqual(new IntKey(5), new IntKey(5));
    }

    /**
        The Int field group at the signed 32-bit limits. The two limits in
        both operand orders separate a value comparison from a subtraction
        whose result leaves the Int range. This function runs in its own
        process, so a crash here leaves the other cases recorded.
    **/
    public static function intExtremes():String {
        return "minMax="
            + intPair(new IntKey(intMinimum()), new IntKey(intMaximum()))
            + "|maxMin="
            + intPair(new IntKey(intMaximum()), new IntKey(intMinimum()))
            + "|equal="
            + intEqual(new IntKey(intMinimum()), new IntKey(intMinimum()));
    }

    /**
        The direct std.ReadOnlyArray<Int> field group: unequal singletons,
        equal collections, a proper prefix, and a pair whose later element
        would reverse the direction that the first unequal element states.
    **/
    public static function arrayOrder():String {
        return "singleton=" + arrayPair(new ArrayKey([1]), new ArrayKey([2])) + "|swapped=" + arrayPair(new ArrayKey([2]), new ArrayKey([1]))
            + "|equalCollection=" + arrayEqual(new ArrayKey([1, 2]), new ArrayKey([1, 2])) + "|prefix=" + arrayPair(new ArrayKey([1]), new ArrayKey([1, 2]))
            + "|prefixSwapped=" + arrayPair(new ArrayKey([1, 2]), new ArrayKey([1])) + "|firstUnequal="
            + arrayPair(new ArrayKey([1, 9]), new ArrayKey([2, 0])) + "|firstUnequalSwapped=" + arrayPair(new ArrayKey([2, 0]), new ArrayKey([1, 9]));
    }

    /**
        The Null<std.ReadOnlyArray<Int>> field group. Every operand is a
        present record; the field of an operand is the absent side where the
        case needs it. The absent field sorts before every present field,
        two absent fields compare equal, and two present fields compare by
        the collection rule. Outer absence and the element comparison stay
        separate observations, so `absentAbsent` reports the field equality
        and `absentPresent` reports the null ordering before any element is
        read.
    **/
    public static function nullableOrder():String {
        return "absentAbsent="
            + nullableEqual(new NullableArrayKey(null), new NullableArrayKey(null))
            + "|absentPresent="
            + nullablePair(new NullableArrayKey(null), new NullableArrayKey([1]))
            + "|presentAbsent="
            + nullablePair(new NullableArrayKey([1]), new NullableArrayKey(null))
            + "|presentEqual="
            + nullableEqual(new NullableArrayKey([1]), new NullableArrayKey([1]))
            + "|presentUnequal="
            + nullablePair(new NullableArrayKey([1]), new NullableArrayKey([2]))
            + "|presentUnequalSwapped="
            + nullablePair(new NullableArrayKey([2]), new NullableArrayKey([1]));
    }

    /**
        The String field group: equal strings, ASCII direction, and the
        pair whose UTF-16 code-unit order disagrees with scalar-value order.
        U+10000 holds the leading surrogate 0xD800, which sorts before the
        single unit 0xE000; the scalar order would put U+E000 first.
    **/
    public static function stringOrder():String {
        return "equal="
            + stringEqual(new StringKey("abc"), new StringKey("abc"))
            + "|ascii="
            + stringPair(new StringKey("a"), new StringKey("b"))
            + "|asciiSwapped="
            + stringPair(new StringKey("b"), new StringKey("a"))
            + "|astral="
            + stringPair(new StringKey("\u{10000}"), new StringKey("\u{E000}"))
            + "|astralSwapped="
            + stringPair(new StringKey("\u{E000}"), new StringKey("\u{10000}"));
    }

    public static function nullableIntOrder():String {
        return "twoTen=" + nullableIntPair(new NullableIntKey(2), new NullableIntKey(10))
            + "|minusTwoOne=" + nullableIntPair(new NullableIntKey(-2), new NullableIntKey(1));
    }

    public static function mixedSignArrayOrder():String {
        return mixedSignArrayPair(new MixedSignArrayKey([-2, 1]), new MixedSignArrayKey([1]));
    }

    /** Both records use the same enum in this module. Reverse insertion order
        makes each sorted table require its own generated enum helper. */
    public static function sharedEnumHelpers():String {
        final first:SortedMapBuilder<FirstSharedEnumKey, String> = SortedMap.builder();
        first.put(new FirstSharedEnumKey(SharedSecond), "B");
        first.put(new FirstSharedEnumKey(SharedFirst), "A");
        final second:SortedMapBuilder<SecondSharedEnumKey, String> = SortedMap.builder();
        second.put(new SecondSharedEnumKey(SharedSecond), "B");
        second.put(new SecondSharedEnumKey(SharedFirst), "A");
        final firstTable = first.build();
        final secondTable = second.build();
        return "first=" + firstTable.valueAt(0) + firstTable.valueAt(1)
            + ";second=" + secondTable.valueAt(0) + secondTable.valueAt(1);
    }

#if swift_output
    /** Two private records share a short name across separate source modules.
        Both comparator calls enter one generated Swift library. */
    public static function sameShortRecordHelpers():String {
        return "left=" + LeftSameKeyCase.observe() + ";right=" + RightSameKeyCase.observe();
    }
#end

    /**
        The signed 32-bit limits, written so the source states them without
        an integer literal outside the Int range.
    **/
    static function intMinimum():Int {
        return -2147483647 - 1;
    }

    static function intMaximum():Int {
        return 2147483647;
    }

    /** Both operand orders of one pair, as `forward;backward`. */
    static function intPair(left:IntKey, right:IntKey):String {
        return intTable(left, "A", right, "B") + ";" + intTable(right, "B", left, "A");
    }

    static function intTable(first:IntKey, firstValue:String, second:IntKey, secondValue:String):String {
        final builder:SortedMapBuilder<IntKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    /** One pair with equal keys, as the collapsed entry. */
    static function intEqual(first:IntKey, second:IntKey):String {
        final builder:SortedMapBuilder<IntKey, String> = SortedMap.builder();
        builder.put(first, "A");
        builder.put(second, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }

    static function arrayPair(left:ArrayKey, right:ArrayKey):String {
        return arrayTable(left, "A", right, "B") + ";" + arrayTable(right, "B", left, "A");
    }

    static function arrayTable(first:ArrayKey, firstValue:String, second:ArrayKey, secondValue:String):String {
        final builder:SortedMapBuilder<ArrayKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    static function arrayEqual(first:ArrayKey, second:ArrayKey):String {
        final builder:SortedMapBuilder<ArrayKey, String> = SortedMap.builder();
        builder.put(first, "A");
        builder.put(second, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }

    static function nullablePair(left:NullableArrayKey, right:NullableArrayKey):String {
        return nullableTable(left, "A", right, "B") + ";" + nullableTable(right, "B", left, "A");
    }

    static function nullableTable(first:NullableArrayKey, firstValue:String, second:NullableArrayKey, secondValue:String):String {
        final builder:SortedMapBuilder<NullableArrayKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    static function nullableEqual(first:NullableArrayKey, second:NullableArrayKey):String {
        final builder:SortedMapBuilder<NullableArrayKey, String> = SortedMap.builder();
        builder.put(first, "A");
        builder.put(second, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }

    static function stringPair(left:StringKey, right:StringKey):String {
        return stringTable(left, "A", right, "B") + ";" + stringTable(right, "B", left, "A");
    }

    static function stringTable(first:StringKey, firstValue:String, second:StringKey, secondValue:String):String {
        final builder:SortedMapBuilder<StringKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    static function stringEqual(first:StringKey, second:StringKey):String {
        final builder:SortedMapBuilder<StringKey, String> = SortedMap.builder();
        builder.put(first, "A");
        builder.put(second, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }

    static function nullableIntPair(left:NullableIntKey, right:NullableIntKey):String {
        return nullableIntTable(left, "A", right, "B") + ";" + nullableIntTable(right, "B", left, "A");
    }

    static function nullableIntTable(first:NullableIntKey, firstValue:String, second:NullableIntKey, secondValue:String):String {
        final builder:SortedMapBuilder<NullableIntKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    static function mixedSignArrayPair(left:MixedSignArrayKey, right:MixedSignArrayKey):String {
        return mixedSignArrayTable(left, "A", right, "B") + ";" + mixedSignArrayTable(right, "B", left, "A");
    }

    static function mixedSignArrayTable(first:MixedSignArrayKey, firstValue:String, second:MixedSignArrayKey, secondValue:String):String {
        final builder:SortedMapBuilder<MixedSignArrayKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }
}
