package tests;

import boring.UStringResidentOps;
import std.Test;

class UStringResidentTests {
    @:test("UString member calls resolve through the Dart runtime resident")
    public static function testResidentMembers():Void {
        Test.equals(6, UStringResidentOps.count("tiqian"));
        Test.equals(105, UStringResidentOps.at("tiqian", 1));
        Test.equals("iq", UStringResidentOps.slice("tiqian", 1, 3));
        Test.equals("一", UStringResidentOps.fromCodePoint(0x4E00));
    }
}
