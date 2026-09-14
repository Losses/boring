package tests;

import boring.BoxedInterfaceDefaultOps;
import std.Test;

class BoxedInterfaceDefaultOpsTests {
    @:test("a concrete interface default boxes in the coalescing closure")
    public static function defaultBoxes():Void {
        #if rust_output
        final withDefault = new BoxedInterfaceDefaultOps();
        Test.equals("filled", withDefault.describe(), "default style");
        #end
    }
}
