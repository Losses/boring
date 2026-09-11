package tests;

import std.Test;

#if swift_output
import boring.SwitchNullArmOps;
import boring.SwitchNullArmOps.SwitchNullTone;
#end

class SwitchNullArmTests {
    @:test("a null variant arm lowers to a unit statement")
    public static function testLabel():Void {
        #if swift_output
        Test.equals("", SwitchNullArmOps.label(SwitchNullTone.Plain));
        Test.equals("rising", SwitchNullArmOps.label(SwitchNullTone.Rising));
        Test.equals("falling", SwitchNullArmOps.label(SwitchNullTone.Falling));
        #else
        Test.equals(true, true);
        #end
    }
}
