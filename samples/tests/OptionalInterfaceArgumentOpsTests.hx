package tests;

import boring.OptionalInterfaceArgumentOps;
import std.Test;

class OptionalInterfaceArgumentOpsTests {
    @:test("a concrete implementor boxes once into an optional interface argument")
    public static function render():Void {
        #if rust_output
        Test.equals("circle", OptionalInterfaceArgumentOps.renderFresh());
        Test.equals("square", OptionalInterfaceArgumentOps.renderLocal(OptionalInterfaceArgumentOps.makeSquare()));
        Test.equals("none", OptionalInterfaceArgumentOps.renderNullableLocal(null));
        #end
    }
}
