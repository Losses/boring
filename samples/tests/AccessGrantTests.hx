package tests;

import std.Test;

#if swift_output
import boring.AccessPeer;
import boring.AccessTarget;
#end

class AccessGrantTests {
    @:test("an @:access peer reads private members across classes")
    public static function testAccessGrant():Void {
        #if swift_output
        final peer = new AccessPeer(new AccessTarget(20));
        Test.equals(40, peer.readThrough());
        #else
        Test.equals(true, true);
        #end
    }
}
