package tests;

import std.Test;

#if swift_output
import boring.OptionalMemberOps;
#end

class OptionalMemberTests {
    @:test("a narrowed nullable receiver unwraps at its member read")
    public static function testMember():Void {
        #if swift_output
        Test.equals(true, OptionalMemberOps.prefix("abc"));
        Test.equals(false, OptionalMemberOps.prefix("xyz"));
        Test.equals(false, OptionalMemberOps.prefix(null));

        Test.equals(true, OptionalMemberOps.notNaN(1.5));
        Test.equals(false, OptionalMemberOps.notNaN(null));

        Test.equals(true, OptionalMemberOps.finite(1.5));
        Test.equals(false, OptionalMemberOps.finite(null));
        #else
        Test.equals(true, true);
        #end
    }
}
