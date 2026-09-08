package tests;

import std.Test;
import boring.WidgetKind.WidgetBuilder;
import boring.WidgetCart.WidgetLens;
import boring.WidgetAssembly;

class WidgetCoalescingTests {
    @:test("coalescing default constructs builder with omitted defaults")
    public static function builderDefault():Void {
        final made = WidgetAssembly.build();
        Test.equals(1, made.scale);
        Test.equals(2, made.bias);
    }

    @:test("coalescing default constructs lens in non-main-class module")
    public static function lensDefault():Void {
        Test.equals(3, WidgetAssembly.lens().zoom);
    }
}
