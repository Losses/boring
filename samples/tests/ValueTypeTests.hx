package tests;

import boring.ValueTypeConsumer;
import std.Test;

/** Runtime hooks for the value-wrapper extension on every target. */
class ValueTypeTests {
    @:test("value wrapper arithmetic and member call")
    public static function testArithmetic():Void {
        Test.equals(6.0, ValueTypeConsumer.arithmetic());
    }

    @:test("equal wrapper representations compare equal")
    public static function testEquality():Void {
        Test.equals(true, ValueTypeConsumer.equalRepresentations());
    }

    @:test("value wrapper static field is preserved")
    public static function testStaticField():Void {
        Test.equals(0.0, ValueTypeConsumer.staticValue());
    }

    @:test("validating wrapper rejects blank construction")
    public static function testBlankRejected():Void {
        Test.equals(true, ValueTypeConsumer.blankRejected());
    }

    @:test("declared wrapper toString returns its representation")
    public static function testRenderedString():Void {
        Test.equals("face", ValueTypeConsumer.renderedId());
    }
}
