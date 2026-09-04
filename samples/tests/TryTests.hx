package tests;

import boring.TryOps;
import boring.VectorError;
import std.Test;

class TryTests {
    @:test("statement region catches overflow into the handler")
    public static function testCaughtStatement():Void {
        Test.equals(12, TryOps.caughtStatement(12));
        Test.equals(14, TryOps.caughtStatement(7));
    }

    @:test("return region yields the handler value on fault")
    public static function testRegionReturn():Void {
        Test.equals(12, TryOps.regionReturn(12));
        Test.equals(16, TryOps.regionReturn(8));
    }

    @:test("initializer region binds the region value")
    public static function testRegionValue():Void {
        Test.equals(13, TryOps.regionValue(12));
        Test.equals(17, TryOps.regionValue(8));
    }

    @:test("handler return leaves the region through the handler")
    public static function testHandlerReturn():Void {
        Test.equals(12, TryOps.handlerReturn(12));
        Test.equals(16, TryOps.handlerReturn(8));
    }

    @:test("message accessor derives from the variant")
    public static function testRegionMessage():Void {
        Test.equals("no fault", TryOps.regionMessage(7));
        Test.equals("record count exceeds u32", TryOps.regionMessage(12));
    }

    @:test("payload capture flows through the catch variable")
    public static function testFaultPayload():Void {
        Test.equals(35, TryOps.faultPayload(5));
    }

    @:test("classify fault maps every variant")
    public static function testClassifyFault():Void {
        Test.equals(11, TryOps.classifyFault(VectorError.BadMagic));
        Test.equals(12, TryOps.classifyFault(VectorError.CountOverflow));
        Test.equals(13, TryOps.classifyFault(VectorError.UnexpectedEof));
        Test.equals(24, TryOps.classifyFault(VectorError.TrailingBytes(4)));
    }
}
