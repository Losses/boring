package tests;

import std.Test;

#if dart_output
import boring.DartCoalesceStaticOps;
import boring.DartCoalesceReceiver;
#end

class DartCoalesceStaticTests {
    @:test("omitted constructor defaults resolve through coalescing statics")
    public static function testPreset():Void {
        #if dart_output
        Test.equals(7, DartCoalesceStaticOps.preset().mode);
        Test.equals(5, DartCoalesceStaticOps.preset().kind);
        Test.equals(3, DartCoalesceStaticOps.custom(3).mode);
        #else
        Test.equals(true, true);
        #end
    }

    @:test("an explicit null argument inlines the cross-module static default")
    public static function testPartial():Void {
        #if dart_output
        Test.equals(2, DartCoalesceReceiver.partial.mode);
        Test.equals(5, DartCoalesceReceiver.partial.kind);
        #else
        Test.equals(true, true);
        #end
    }
}
