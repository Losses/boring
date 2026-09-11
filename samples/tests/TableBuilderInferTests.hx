package tests;

import std.Test;

#if swift_output
import boring.TableBuilderInferOps;
#end

class TableBuilderInferTests {
    @:test("a sorted table builder local pins its value parameter")
    public static function testBuilders():Void {
        #if swift_output
        Test.equals(3, TableBuilderInferOps.sum());
        Test.equals(0, TableBuilderInferOps.emptySize());
        #else
        Test.equals(true, true);
        #end
    }
}
