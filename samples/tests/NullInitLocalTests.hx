package tests;

import std.Test;

#if swift_output
import boring.NullInitLocalOps;
import boring.NullInitLocalOps.NullInitBox;
#end

class NullInitLocalTests {
    @:test("a class local bound to nil names its optional type")
    public static function testPick():Void {
        #if swift_output
        Test.equals(2, NullInitLocalOps.pick([new NullInitBox(1), new NullInitBox(2), new NullInitBox(3)], 2));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a second nil-bound class local names its optional type")
    public static function testLabel():Void {
        #if swift_output
        Test.equals("v2", NullInitLocalOps.label([new NullInitBox(1), new NullInitBox(2)], 2));
        #else
        Test.equals(true, true);
        #end
    }
}
