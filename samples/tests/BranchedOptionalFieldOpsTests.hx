package tests;

import boring.BranchedOptionalFieldOps;
import std.Test;

class BranchedOptionalFieldOpsTests {
    @:test("a branch-assigned optional field keeps the parameter null check")
    public static function penalty():Void {
        #if rust_output
        Test.equals(2, BranchedOptionalFieldOps.penalty());
        Test.equals(9, BranchedOptionalFieldOps.explicit());
        #end
    }

    @:test("a branch-assigned optional float field keeps the parameter null check")
    public static function rate():Void {
        #if rust_output
        Test.equals(0.5, BranchedOptionalFieldOps.rate());
        #end
    }

    @:test("a branch-assigned interface field declares its owned Rust type")
    public static function ruleTag():Void {
        #if rust_output
        Test.equals("concrete", BranchedOptionalFieldOps.ruleTag());
        #end
    }
}
