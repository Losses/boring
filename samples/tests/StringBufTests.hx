package tests;

import boring.StringBufOps;
import std.Test;

class StringBufTests {
    @:test("empty buffer has length zero and empty toString")
    public static function testEmptyBuffer():Void {
        Test.equals("", StringBufOps.buildEmpty());
        Test.equals(0, StringBufOps.measureLength([]));
    }

    @:test("add appends strings and updates length")
    public static function testAddStrings():Void {
        final res = StringBufOps.buildParts("hello", " ", "world");
        Test.equals("hello world", res);
        Test.equals(11, StringBufOps.measureLength(["hello", " ", "world"]));
    }

    @:test("add with supplementary characters counts UTF-16 code units")
    public static function testSupplementaryCharacters():Void {
        Test.equals("hi🚀!", StringBufOps.buildSupplementary());
        Test.equals(5, StringBufOps.measureSupplementaryLength());
    }

    @:test("addChar appends BMP characters")
    public static function testAddChar():Void {
        final res = StringBufOps.buildWithChars("item-", 65, 66);
        Test.equals("item-AB", res);
    }

    @:test("buffer extends after toString calls")
    public static function testIncremental():Void {
        final steps = StringBufOps.buildIncremental();
        Test.equals("step1", steps[0]);
        Test.equals("step1-step2", steps[1]);
    }

    @:test("a lead completed by the immediately following addChar reads as one character")
    public static function testCompletePair():Void {
        Test.equals("😀", StringBufOps.completePair(0xD83D, 0xDE00));
    }

    @:test("a trail without a preceding lead faults with the argument unit")
    public static function testTrailWithoutLead():Void {
        Test.equals(58320, StringBufOps.caughtTrailUnit(0xDC00));
    }

    @:test("a dangling lead observed by toString faults with the held unit")
    public static function testDanglingLead():Void {
        Test.equals(57296, StringBufOps.caughtDanglingUnit(0xD800));
    }

    @:test("an add stranding a held lead faults with the held unit")
    public static function testAddAfterLead():Void {
        Test.equals(57423, StringBufOps.caughtAddAfterLeadUnit(0xD87F));
    }
}
