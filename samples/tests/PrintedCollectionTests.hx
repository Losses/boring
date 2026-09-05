package tests;

import boring.PrintedCollection;
import boring.PrintedCollection.PrintedEnumCollection;
import boring.PrintedCollection.PrintedPoint;
import boring.PrintedCollection.PrintedNullableCollection;
import std.RecordStr;
import std.SortedMap;
import std.Test;

class PrintedCollectionTests {
    @:test("collection fields use the ruled array form")
    public static function collections():Void {
        final v = new PrintedCollection(["alpha", "beta"], [1, 2], [new PrintedPoint(1, 2)], [[1, 2], [3]], []);
        final expected = "PrintedCollection(names=[alpha, beta], counts=[1, 2], points=[PrintedPoint(x=1, y=2)], matrix=[[1, 2], [3]], none=[])";
        Test.equals(expected, v.toString());
        Test.equals(expected, RecordStr.str(v));
    }

    // The member call alone carries this row: the call-site form of a module
    // outside the record's own module still awaits the cross-module enum
    // cast import on the TypeScript target (see PrintedSortedFields).

    @:test("payload enum elements render through the labeled form")
    public static function enumElements():Void {
        final v = new PrintedEnumCollection([Silent, Steps(2)]);
        Test.equals("PrintedEnumCollection(flags=[Silent, Steps(count=2)])", v.toString());
    }

    // A nullable collection field prints null as "null" and a present
    // array through the ruled form (feature spec 33 ruling 4 gap
    // closure; the null comparison of spec 31 ruling 4).

    @:test("nullable collection fields print null and present forms")
    public static function nullableCollectionPrint():Void {
        final none = new PrintedNullableCollection(null);
        Test.equals("PrintedNullableCollection(words=null)", none.toString());
        final present = new PrintedNullableCollection(["alpha", "beta"]);
        Test.equals("PrintedNullableCollection(words=[alpha, beta])", present.toString());
    }

    // A nullable collection field is a legal sorted-table key (spec
    // stdlib/16 ruling 6: a null sorts before every non-null value, two
    // nulls compare equal, and two present arrays compare element-wise
    // then by length). The generated comparators and the stage 1 oracle
    // comparator carry that ordering.

    @:test("nullable collection keys order null, elements, then length")
    public static function nullableCollectionKeys():Void {
        // Two null keys compare equal: the later put survives.
        final doubleNull:SortedMapBuilder<PrintedNullableCollection, String> = SortedMap.builder();
        doubleNull.put(new PrintedNullableCollection(null), "first");
        doubleNull.put(new PrintedNullableCollection(null), "second");
        final doubleNullMap = doubleNull.build();
        Test.equals(1, doubleNullMap.size(), "two null keys collapse to one entry");
        Test.equals("second", doubleNullMap.valueAt(0), "the later null-keyed put survives");

        // A null key sorts before a present key. The value key is put
        // first so the generated target must move the null ahead.
        final nullFirst:SortedMapBuilder<PrintedNullableCollection, String> = SortedMap.builder();
        nullFirst.put(new PrintedNullableCollection(["alpha"]), "value");
        nullFirst.put(new PrintedNullableCollection(null), "null");
        final nullFirstMap = nullFirst.build();
        Test.equals(2, nullFirstMap.size(), "null and value keys stay distinct");
        Test.equals("null", nullFirstMap.valueAt(0), "null sorts before a present array");
        Test.equals("value", nullFirstMap.valueAt(1), "the present key follows the null key");

        // Two keys with equal arrays compare equal: the later put wins.
        final sameElements:SortedMapBuilder<PrintedNullableCollection, String> = SortedMap.builder();
        sameElements.put(new PrintedNullableCollection(["alpha", "beta"]), "first");
        sameElements.put(new PrintedNullableCollection(["alpha", "beta"]), "second");
        final sameElementsMap = sameElements.build();
        Test.equals(1, sameElementsMap.size(), "equal array keys collapse to one entry");
        Test.equals("second", sameElementsMap.valueAt(0), "the later equal-keyed put survives");

        // One array a prefix of the other: the shorter sorts first. The
        // longer key is put first so the generated target must move the
        // shorter ahead.
        final prefixLength:SortedMapBuilder<PrintedNullableCollection, String> = SortedMap.builder();
        prefixLength.put(new PrintedNullableCollection(["alpha", "beta"]), "long");
        prefixLength.put(new PrintedNullableCollection(["alpha"]), "short");
        final prefixLengthMap = prefixLength.build();
        Test.equals(2, prefixLengthMap.size(), "prefix and longer keys stay distinct");
        Test.equals("short", prefixLengthMap.valueAt(0), "a prefix array sorts before its extension");
        Test.equals("long", prefixLengthMap.valueAt(1), "the longer array follows its prefix");
    }
}
