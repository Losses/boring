package tests;

import std.Test;

#if kotlin_output
import boring.ExceptionChainProbe;
#end

class ExceptionChainProbeTests {
    @:test("a null previous on a base exception reads as none")
    public static function nullPrevious():Void {
        #if kotlin_output
        Test.equals("none", ExceptionChainProbe.previousMessage(null));
        #else
        Test.equals(true, true);
        #end
    }
}