package tests;

import std.Test;

#if swift_output
import boring.ForInOptionalOps;
#end

class ForInOptionalTests {
    @:test("a for-in over a guarded nullable array unwraps")
    public static function testIterate():Void {
        #if swift_output
        Test.equals(6, ForInOptionalOps.sum([1, 2, 3]));
        Test.equals(0, ForInOptionalOps.sum(null));

        Test.equals(3, ForInOptionalOps.count([4, 5, 6]));
        Test.equals(0, ForInOptionalOps.count(null));

        Test.equals(15, ForInOptionalOps.fallback([7, 8]));
        Test.equals(0, ForInOptionalOps.fallback(null));
        #else
        Test.equals(true, true);
        #end
    }
}
