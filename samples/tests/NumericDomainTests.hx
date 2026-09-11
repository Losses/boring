package tests;

import boring.NumericDomainOps;
import std.Test;

class NumericDomainTests {
    @:test("A positive-checked index stays unsigned in charCodeAt")
    public static function testPrefixUnit():Void {
        Test.equals(0x41, NumericDomainOps.prefixUnit("AB", 1));
        Test.equals(0, NumericDomainOps.prefixUnit("AB", 0));
    }

    @:test("Loop offsets stay in the u32 domain")
    public static function testOffsets():Void {
        Test.equals(3, NumericDomainOps.offsets("abcd").length);
        Test.equals(1, NumericDomainOps.offsets("abcd")[0]);
        Test.equals(3, NumericDomainOps.offsets("abcd")[2]);
    }

    @:test("A negative sentinel local assigns from a u32 loop index")
    public static function testFindIndex():Void {
        Test.equals(30, NumericDomainOps.findIndex([10, 20, 30], 30));
        Test.equals(0, NumericDomainOps.findIndex([10, 20, 30], 99));
    }

    @:test("An i32 index reaches the u32 charCodeAt slot")
    public static function testBeforeChar():Void {
        Test.equals(0x41, NumericDomainOps.beforeChar("AB", 2));
    }

    @:test("An i32 indexOf result feeds a u32 vec literal")
    public static function testColonPair():Void {
        final pair = NumericDomainOps.colonPair("a:b", 0);
        Test.equals(2, pair.length);
        Test.equals(0, pair[0]);
        Test.equals(2, pair[1]);
        Test.equals(0, NumericDomainOps.colonPair("ab", 0).length);
    }

    @:test("An i32 offset pushes into a u32 array")
    public static function testCollectOffsets():Void {
        Test.equals(3, NumericDomainOps.collectOffsets("abcd").length);
        Test.equals(1, NumericDomainOps.collectOffsets("abcd")[0]);
    }
}