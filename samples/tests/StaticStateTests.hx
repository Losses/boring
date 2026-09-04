package tests;

import boring.StaticStateOps;
import boring.StaticStateOps.StaticStateClient;
import std.Test;

class StaticStateTests {
    @:test("static fields round-trip assignments and retain container state")
    public static function testStaticState():Void {
        StaticStateOps.setCurrent("own");
        Test.equals("own", StaticStateOps.readCurrent(), "assignment from the declaring class");

        StaticStateClient.install("other");
        Test.equals("other", StaticStateOps.readCurrent(), "assignment from another class");

        StaticStateOps.record("first");
        StaticStateOps.record("second");
        Test.equals(2, StaticStateOps.sectionCount(), "static container growth");
        Test.equals("first", StaticStateOps.firstSection(), "first recorded section");

        Test.equals(4096, StaticStateOps.limit, "scalar static constant");
        Test.equals("empty", StaticStateOps.emptyMark, "string static constant");
    }
}
