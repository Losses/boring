package tests;

import boring.InterfaceFieldLiteralOps;
import std.Test;

class InterfaceFieldLiteralOpsTests {
    @:test("an interface-typed literal field boxes the concrete value")
    public static function describe():Void {
        #if rust_output
        Test.equals("tone:alpha", InterfaceFieldLiteralOps.describe());
        #end
    }
}
