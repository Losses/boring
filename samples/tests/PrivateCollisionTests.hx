package tests;

import std.Test;

#if swift_output
import boring.PrivateCollisionAlpha;
import boring.PrivateCollisionBeta;
#end

class PrivateCollisionTests {
    @:test("module-private types of the same name stay file-scoped")
    public static function testPrivateCollision():Void {
        #if swift_output
        Test.equals("alpha", PrivateCollisionAlpha.label());
        Test.equals("beta", PrivateCollisionBeta.label());
        #else
        Test.equals(true, true);
        #end
    }
}
