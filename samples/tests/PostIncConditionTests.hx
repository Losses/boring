package tests;

import std.Test;

#if swift_output
import boring.PostIncConditionOps;
#end

class PostIncConditionTests {
    @:test("a post-increment condition keeps its closure parenthesized")
    public static function testCondition():Void {
        #if swift_output
        Test.equals("first:1", PostIncConditionOps.label(0));
        Test.equals(3, PostIncConditionOps.countTo(3));
        #else
        Test.equals(true, true);
        #end
    }
}
