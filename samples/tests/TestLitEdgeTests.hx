package tests;

import boring.TestLitEdgeOps;
import std.Test;

class TestLitEdgeTests {
    @:test("a non-null literal fills a nullable field inside an array element literal")
    public static function nonNullIntoNullableArrayElemField():Void {
        final edges = TestLitEdgeOps.edgeList();
        Test.equals(10, edges[0].offset);
        Test.equals(4.0, edges[0].inlineStart == null ? -1.0 : (edges[0].inlineStart : Float));
    }

    @:test("a non-null literal fills a nullable field on a direct return")
    public static function nonNullIntoNullableReturnField():Void {
        final e = TestLitEdgeOps.directReturn();
        Test.equals(20, e.offset);
        Test.equals(8.0, e.inlineStart == null ? -1.0 : (e.inlineStart : Float));
    }
}
