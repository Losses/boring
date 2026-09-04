package tests;

import boring.EnumQueriesOps;
import std.Test;

class EnumQueriesTests {
    @:test("enum collections preserve declaration order and constructor names")
    public static function names():Void
        Test.equals("F64,F32,F16", EnumQueriesOps.names());

    @:test("enum collection counts fold through direct and alias reads")
    public static function counts():Void {
        Test.equals(3, EnumQueriesOps.directCount());
        Test.equals(3, EnumQueriesOps.aliasCount());
    }

    @:test("enum name lookup round trips and misses return empty")
    public static function lookup():Void {
        Test.equals(true, EnumQueriesOps.roundTrips());
        Test.equals("empty", EnumQueriesOps.unknown());
    }

    @:test("enum queries cover a second value enumeration")
    public static function second():Void
        Test.equals("Read,Write", EnumQueriesOps.secondEnum());
}
