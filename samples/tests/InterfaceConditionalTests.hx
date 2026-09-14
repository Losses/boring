package tests;

import boring.InterfaceConditionalOps;
import std.Test;

class InterfaceConditionalTests {
    @:test("a conditional interface result boxes each concrete arm")
    public static function chooseText():Void {
        #if rust_output
        Test.equals("alpha", InterfaceConditionalOps.chooseText(true));
        Test.equals("beta", InterfaceConditionalOps.chooseText(false));
        #end
    }
}
