package tests;

import std.Test;

#if swift_output
import std.UStringException;
import boring.InterfaceThrowOps;
#end

class InterfaceThrowTests {
    @:test("only a throwing implementation lifts the interface requirement")
    public static function testInterfaceThrows():Void {
        #if swift_output
        final clean = InterfaceThrowOps.clean();
        final faulty = InterfaceThrowOps.faulty();
        Test.equals(2, InterfaceThrowOps.viaInterface(clean, 1));
        final caught = try {
            InterfaceThrowOps.viaInterface(faulty, -1);
            false;
        } catch (error:UStringException) {
            true;
        };
        Test.equals(true, caught);
        #else
        Test.equals(true, true);
        #end
    }
}
