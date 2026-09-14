package tests;

import std.Test;

#if rust_output
import boring.HaxeExceptionOps.HaxeExceptionFault;
import boring.InterfaceUnionOps.InterfaceUnionAlpha;
import boring.InterfaceUnionBeta;
import boring.InterfaceUnionOps;
import boring.ValueException;
#end

class InterfaceUnionTests {
    @:test("an interface method with disagreeing fault domains shares one union")
    public static function sharedUnion():Void {
        #if rust_output
        Test.equals(5, InterfaceUnionOps.call(new InterfaceUnionAlpha(), 5));
        Test.equals(6, InterfaceUnionOps.call(new InterfaceUnionBeta(), 6));

        var alphaCaught = false;
        try {
            InterfaceUnionOps.call(new InterfaceUnionAlpha(), -1);
        } catch (error:HaxeExceptionFault) {
            alphaCaught = true;
        }
        Test.equals(true, alphaCaught);

        var betaCaught = false;
        try {
            InterfaceUnionOps.call(new InterfaceUnionBeta(), 0);
        } catch (error:ValueException) {
            betaCaught = true;
        }
        Test.equals(true, betaCaught);
        #else
        Test.equals(true, true);
        #end
    }
}
