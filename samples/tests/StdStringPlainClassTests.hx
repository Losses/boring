package tests;

import boring.StdStringPlainClassOps.PlainClassRecord;
import boring.StdStringPlainClassOps.PlainPoint;
import std.Test;

class StdStringPlainClassTests {
    @:test("Std.string accepts ordinary classes with toString")
    public static function plainClassAndRecord():Void {
        final point = new PlainPoint(2, 3);
        final plainText = Std.string(point);
        final record = new PlainClassRecord(point, [new PlainPoint(4, 5), new PlainPoint(6, 7)]);
        Test.equals("Point(2,3)", plainText);
        Test.equals("PlainClassRecord(point=Point(2,3), points=[Point(4,5), Point(6,7)])", record.toString());
        Test.equals("plain=Point(2,3); record=PlainClassRecord(point=Point(2,3), points=[Point(4,5), Point(6,7)])",
            "plain="
            + plainText
            + "; record="
            + record.toString());
    }
}
