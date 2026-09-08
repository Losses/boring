package tests;

import boring.TraitSignOps.TraitSignOpsRunner;
import std.Test;

class TraitSignTests {
    @:test("interface methods cover plain fallible and mutating signatures")
    public static function signatures():Void {
        Test.equals("trait:1", TraitSignOpsRunner.run());
    }
}
