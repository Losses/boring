package tests;

import boring.EnumSortedKeysOps;
import std.Test;

class EnumSortedKeysTests {
    @:test("Parameterless enum sorted sets use declaration order")
    public static function testSetOrder():Void {
        Test.equals("Low,Mid,High", EnumSortedKeysOps.describe(), "set traversal follows declaration order");
        Test.equals(true, EnumSortedKeysOps.has(), "set has finds enum singleton");
    }

    @:test("Parameterless enum sorted maps order keys and values")
    public static function testMapOrder():Void {
        Test.equals("Low:1;Mid:2;High:3", EnumSortedKeysOps.mapOrder(), "map indexes follow declaration order");
        Test.equals("Later,Earlier", EnumSortedKeysOps.declarationOrder(), "source constructor order is authoritative");
    }
}
