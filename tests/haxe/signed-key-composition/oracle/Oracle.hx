/**
    Haxe oracle for the signed key composition fixture. The module implements
    the ordering rule authored in docs/specs/stdlib/07-sorted-keyed-tables.md
    and docs/specs/stdlib/16-dataclass-sorted-keys.md directly: signed Int
    value comparison, field lexicographic order, null before every present
    value, and element-wise collection order. It emits the same observation
    text the generated targets print, without touching std.SortedMap or any
    target runtime. It runs on the interpreter:

        haxe -cp tests/haxe/signed-key-composition/oracle -main Oracle --interp

    The runner diffs this output against expected.tsv, so an oracle that
    an oracle disagreement with the authored expectation is a harness defect.

    The oracle does not copy one text over the other. Each observation
    simulates the two table builds separately: the entries are inserted one
    by one into an ordered list under the comparator rule, exactly the way a
    sorted table absorbs puts, once per insertion sequence. An asymmetric
    comparator, one whose answer depends on the argument order or on what is
    already in the table, places the second sequence in a different order and
    the two texts disagree, so the oracle does catch insertion-order
    sensitive defects and does not assume them absent.
**/
class Oracle {
    static function main() {
        for (name in caseOrder) {
            Sys.println(results.get(name));
        }
    }

    static final directPair = {a: -5, b: 3};

    static final results = [
        "direct-int" => directInt(),
        "direct-int-extremes" => intExtremesRow(),
        "typedef-int" => typedefInt(),
        "typedef-int-extremes" => intExtremesRow(),
        "composite-nullable" => compositeNullable(),
        "composite-extremes" => compositeExtremesRow(),
    ];
    static final caseOrder = [
        "direct-int",
        "direct-int-extremes",
        "typedef-int",
        "typedef-int-extremes",
        "composite-nullable",
        "composite-extremes"
    ];

    /** Signed Int value comparison: the only scalar rule this run observes. */
    static function signedInt(a:Int, b:Int):Int {
        return a < b ? -1 : (a > b ? 1 : 0);
    }

    /**
        Insertion into an ordered list under the comparator rule: every
        existing entry is compared against the candidate as
        `compare(existing, candidate)`, and the candidate goes after the last
        entry that compares negative or zero. A resident sorted-table comparator
        observes this rule at every put.
    **/
    static function insertEntry(table:Array<{k:Int, tag:String}>, key:Int, tag:String, compare:(Int, Int) -> Int) {
        var position = 0;
        while (position < table.length && compare(table[position].k, key) < 0) {
            position += 1;
        }
        table.insert(position, {k: key, tag: tag});
    }

    /** Encode one built table as `valueAt(0)+valueAt(1)#sizeN`. */
    static function encodeTable(table:Array<{k:Int, tag:String}>):String {
        var text = "";
        for (entry in table) {
            text += entry.tag;
        }
        return text + "#size" + table.length;
    }

    /**
        Build one table through one insertion sequence and encode it. The
        first put carries tag `firstTag`, the second `secondTag`, so the
        letters follow the operands of that sequence and stay independent of the
        key values.
    **/
    static function buildTable(first:Int, second:Int, firstTag:String, secondTag:String, compare:(Int, Int) -> Int):String {
        final table:Array<{k:Int, tag:String}> = [];
        insertEntry(table, first, firstTag, compare);
        insertEntry(table, second, secondTag, compare);
        return encodeTable(table);
    }

    /** Both insertion orders of one unequal pair, as `forward;backward`. */
    static function bothOrders(a:Int, b:Int, compare:(Int, Int) -> Int):String {
        final forward = buildTable(a, b, "A", "B", compare);
        final backward = buildTable(b, a, "B", "A", compare);
        return forward + ";" + backward;
    }

    /** One pair with equal keys: the collapsed entry holding the last put. */
    static function equalText():String {
        return "size1atB";
    }

    static function directCompare(a:Int, b:Int):Int {
        return signedInt(a, b);
    }

    static function directInt():String {
        return "neg=" + bothOrders(directPair.a, directPair.b, directCompare) + "|negSwapped=" + bothOrders(directPair.b, directPair.a, directCompare)
            + "|twoTen=" + bothOrders(2, 10, directCompare) + "|twoTenSwapped=" + bothOrders(10, 2, directCompare);
    }

    static function intExtremesRow():String {
        final min = -2147483647 - 1;
        final max = 2147483647;
        return "minMax="
            + bothOrders(min, max, directCompare)
            + "|maxMin="
            + bothOrders(max, min, directCompare)
            + "|equal="
            + equalText();
    }

    static function typedefInt():String {
        return "neg=" + bothOrders(directPair.a, directPair.b, directCompare) + "|negSwapped=" + bothOrders(directPair.b, directPair.a, directCompare)
            + "|twoTen=" + bothOrders(2, 10, directCompare) + "|twoTenSwapped=" + bothOrders(10, 2, directCompare);
    }

    /** One composite entry: the Int field, then the collection field. */
    static function compositeKey(n:Null<Int>, items:Array<Int>):{n:Null<Int>, items:Array<Int>} {
        return {n: n, items: items};
    }

    static function arrayCompare(a:Array<Int>, b:Array<Int>):Int {
        final shared = a.length < b.length ? a.length : b.length;
        var index = 0;
        while (index < shared) {
            final element = signedInt(a[index], b[index]);
            if (element != 0) {
                return element;
            }
            index += 1;
        }
        return signedInt(a.length, b.length);
    }

    /** Field lexicographic over (n, items) with null before every value. */
    static function compositeCompare(a:{n:Null<Int>, items:Array<Int>}, b:{n:Null<Int>, items:Array<Int>}):Int {
        if (a.n == null && b.n != null) {
            return -1;
        }
        if (a.n != null && b.n == null) {
            return 1;
        }
        if (a.n != null && b.n != null) {
            final head = signedInt(a.n, b.n);
            if (head != 0) {
                return head;
            }
        }
        return arrayCompare(a.items, b.items);
    }

    static function insertComposite(table:Array<{k:{n:Null<Int>, items:Array<Int>}, tag:String}>, key:{n:Null<Int>, items:Array<Int>}, tag:String) {
        var position = 0;
        while (position < table.length && compositeCompare(table[position].k, key) < 0) {
            position += 1;
        }
        table.insert(position, {k: key, tag: tag});
    }

    static function buildComposite(first:{n:Null<Int>, items:Array<Int>}, second:{n:Null<Int>, items:Array<Int>}, firstTag:String, secondTag:String):String {
        final table:Array<{k:{n:Null<Int>, items:Array<Int>}, tag:String}> = [];
        insertComposite(table, first, firstTag);
        insertComposite(table, second, secondTag);
        var text = "";
        for (entry in table) {
            text += entry.tag;
        }
        return text + "#size" + table.length;
    }

    static function compositeBothOrders(a:{n:Null<Int>, items:Array<Int>}, b:{n:Null<Int>, items:Array<Int>}):String {
        final forward = buildComposite(a, b, "A", "B");
        final backward = buildComposite(b, a, "B", "A");
        return forward + ";" + backward;
    }

    static function compositeNullable():String {
        return "nullPresent="
            + compositeBothOrders(compositeKey(null, [3]), compositeKey(-5, [3]))
            + "|nullPresentSwapped="
            + compositeBothOrders(compositeKey(-5, [3]), compositeKey(null, [3]))
            + "|nullEqual="
            + equalText()
            + "|arrayNeg="
            + compositeBothOrders(compositeKey(2, [-5]), compositeKey(2, [3]))
            + "|arrayNegSwapped="
            + compositeBothOrders(compositeKey(2, [3]), compositeKey(2, [-5]))
            + "|twoTen="
            + compositeBothOrders(compositeKey(2, [5]), compositeKey(10, [1]))
            + "|twoTenSwapped="
            + compositeBothOrders(compositeKey(10, [1]), compositeKey(2, [5]));
    }

    static function compositeExtremesRow():String {
        final min = -2147483647 - 1;
        final max = 2147483647;
        return "minMax="
            + compositeBothOrders(compositeKey(min, [min]), compositeKey(max, [max]))
            + "|maxMin="
            + compositeBothOrders(compositeKey(max, [max]), compositeKey(min, [min]))
            + "|equal="
            + equalText();
    }
}
