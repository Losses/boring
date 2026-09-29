package composition;

import std.ReadOnlyArray;
import std.SortedMap;

/**
    Authored observation module for the signed key composition fixture. Three
    key shapes ride one module under distinct names, so each observation
    answers one shape question of stdlib spec 07 and spec 16:

    1. The direct `Int` key takes the plain integer path (spec 16 kind 1
       through spec 07 kind 1).
    2. The single-field typedef anonymous structure takes the spec 07
       structure-key path, whose per-target scalar rule this run observes.
    3. The `@:dataClass` record carries `Null<Int>` and
       `std.ReadOnlyArray<Int>` (spec 16 kinds 1, 5 and 6) in declaration
       order.

    The module states no ordering rule of its own. Every function builds
    sorted tables through std.SortedMap, the source operation that binds the
    resident comparator of its key type, and reports the table order it
    observes. The observation text encodes the first and second table values
    and the entry count, so one line carries direction, asymmetry and
    equality; every unequal pair is observed through both insertion orders of
    one table, joined by `;`.
**/
typedef SingleFieldKey = {
    final v:Int;
}

@:dataClass
class CompositeKey {
    public final n:Null<Int>;
    public final items:ReadOnlyArray<Int>;

    public function new(n:Null<Int>, items:ReadOnlyArray<Int>) {
        this.n = n;
        this.items = items;
    }
}

class KeyCompositionObserve {
    /**
        The direct Int key group: the negative pair and the 2/10 pair, whose
        numeric order disagrees with the character order of their decimal
        forms, in both operand orders each.
    **/
    public static function directInt():String {
        return "neg="
            + directPair(-5, 3)
            + "|negSwapped="
            + directPair(3, -5)
            + "|twoTen="
            + directPair(2, 10)
            + "|twoTenSwapped="
            + directPair(10, 2);
    }

    /**
        The direct Int key at the signed 32-bit limits, in both operand
        orders. This function runs in its own process, so a crash inside the
        generated comparison leaves the other cases recorded.
    **/
    public static function directIntExtremes():String {
        return "minMax=" + directPair(intMinimum(), intMaximum()) + "|maxMin=" + directPair(intMaximum(), intMinimum()) + "|equal="
            + directEqual(intMinimum(), intMinimum());
    }

    /**
        The single-field typedef structure group over the same values as the
        direct group, so the structure-key scalar rule is observed against
        the direct rule on the same operands.
    **/
    public static function typedefInt():String {
        return "neg="
            + typedefPair(-5, 3)
            + "|negSwapped="
            + typedefPair(3, -5)
            + "|twoTen="
            + typedefPair(2, 10)
            + "|twoTenSwapped="
            + typedefPair(10, 2);
    }

    /**
        The single-field typedef structure group at the signed 32-bit
        limits, in its own process for the same crash-isolation reason.
    **/
    public static function typedefIntExtremes():String {
        return "minMax=" + typedefPair(intMinimum(), intMaximum()) + "|maxMin=" + typedefPair(intMaximum(), intMinimum()) + "|equal="
            + typedefEqual(intMinimum(), intMinimum());
    }

    /**
        The dataClass group: outer null ordering over a present negative
        value, equal nulls with equal collections, a negative element inside
        the collection field under an equal Int field, and the 2/10 order on
        the Int field ahead of the collection field.
    **/
    public static function compositeNullable():String {
        return "nullPresent="
            + compositePair(new CompositeKey(null, [3]), new CompositeKey(-5, [3]))
            + "|nullPresentSwapped="
            + compositePair(new CompositeKey(-5, [3]), new CompositeKey(null, [3]))
            + "|nullEqual="
            + compositeEqual(new CompositeKey(null, [1, 2]), new CompositeKey(null, [1, 2]))
            + "|arrayNeg="
            + compositePair(new CompositeKey(2, [-5]), new CompositeKey(2, [3]))
            + "|arrayNegSwapped="
            + compositePair(new CompositeKey(2, [3]), new CompositeKey(2, [-5]))
            + "|twoTen="
            + compositePair(new CompositeKey(2, [5]), new CompositeKey(10, [1]))
            + "|twoTenSwapped="
            + compositePair(new CompositeKey(10, [1]), new CompositeKey(2, [5]));
    }

    /**
        The dataClass group at the signed 32-bit limits on both fields, in
        its own process.
    **/
    public static function compositeExtremes():String {
        return "minMax="
            + compositePair(new CompositeKey(intMinimum(), [intMinimum()]), new CompositeKey(intMaximum(), [intMaximum()]))
            + "|maxMin="
            + compositePair(new CompositeKey(intMaximum(), [intMaximum()]), new CompositeKey(intMinimum(), [intMinimum()]))
            + "|equal="
            + compositeEqual(new CompositeKey(intMinimum(), [intMinimum()]), new CompositeKey(intMinimum(), [intMinimum()]));
    }

    /** The signed 32-bit limits, written without an out-of-range literal. */
    static function intMinimum():Int {
        return -2147483647 - 1;
    }

    static function intMaximum():Int {
        return 2147483647;
    }

    /** Both insertion orders of one unequal pair, as `forward;backward`. */
    static function directPair(first:Int, second:Int):String {
        return directTable(first, "A", second, "B") + ";" + directTable(second, "B", first, "A");
    }

    static function directTable(first:Int, firstValue:String, second:Int, secondValue:String):String {
        final builder:SortedMapBuilder<Int, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    static function directEqual(first:Int, second:Int):String {
        final builder:SortedMapBuilder<Int, String> = SortedMap.builder();
        builder.put(first, "A");
        builder.put(second, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }

    /** Both insertion orders of one unequal structure pair, as `forward;backward`. */
    static function typedefPair(first:Int, second:Int):String {
        return typedefTable(first, "A", second, "B") + ";" + typedefTable(second, "B", first, "A");
    }

    static function typedefTable(first:Int, firstValue:String, second:Int, secondValue:String):String {
        return boxTable({v: first}, firstValue, {v: second}, secondValue);
    }

    static function typedefEqual(first:Int, second:Int):String {
        final builder:SortedMapBuilder<SingleFieldKey, String> = SortedMap.builder();
        builder.put({v: first}, "A");
        builder.put({v: second}, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }

    static function boxTable(first:SingleFieldKey, firstValue:String, second:SingleFieldKey, secondValue:String):String {
        final builder:SortedMapBuilder<SingleFieldKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    /** Both insertion orders of one unequal composite pair, as `forward;backward`. */
    static function compositePair(first:CompositeKey, second:CompositeKey):String {
        return compositeTable(first, "A", second, "B") + ";" + compositeTable(second, "B", first, "A");
    }

    static function compositeTable(first:CompositeKey, firstValue:String, second:CompositeKey, secondValue:String):String {
        final builder:SortedMapBuilder<CompositeKey, String> = SortedMap.builder();
        builder.put(first, firstValue);
        builder.put(second, secondValue);
        final table = builder.build();
        return table.valueAt(0) + table.valueAt(1) + "#size" + table.size();
    }

    static function compositeEqual(first:CompositeKey, second:CompositeKey):String {
        final builder:SortedMapBuilder<CompositeKey, String> = SortedMap.builder();
        builder.put(first, "A");
        builder.put(second, "B");
        final table = builder.build();
        return "size" + table.size() + "at" + table.valueAt(0);
    }
}
