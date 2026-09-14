package tests;

import boring.NullableInterfaceBranchOps;
import std.Test;

class NullableInterfaceBranchOpsTests {
    @:test("a nullable interface conditional boxes its concrete arm")
    public static function label():Void {
        #if rust_output
        Test.equals("alpha", NullableInterfaceBranchOps.label(true));
        Test.equals("none", NullableInterfaceBranchOps.label(false));
        #end
    }
}
