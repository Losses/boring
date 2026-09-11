package tests;

import std.Test;

#if swift_output
import boring.DefaultParamUnwrapOps;
#end

class DefaultParamUnwrapTests {
    @:test("a constant-default parameter is plain in Swift and never unwraps")
    public static function testDefaults():Void {
        #if swift_output
        final a = new DefaultParamUnwrapOps();
        Test.equals(3, a.mode);
        Test.equals(true, a.flag);
        Test.equals(true, a.combine());
        Test.equals(false, a.combine(false));
        Test.equals(true, a.forward());
        Test.equals(false, a.forward(false));

        final b = new DefaultParamUnwrapOps(7, false);
        Test.equals(7, b.mode);
        Test.equals(false, b.flag);
        Test.equals(false, b.combine());
        #else
        Test.equals(true, true);
        #end
    }
}
