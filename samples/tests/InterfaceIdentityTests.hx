package tests;

import std.Test;

#if swift_output
import boring.InterfaceIdentityOps;
#end

class InterfaceIdentityTests {
    @:test("an interface value compares by identity in Swift without a class constraint")
    public static function testIdentity():Void {
        #if swift_output
        final leaf = InterfaceIdentityOps.leaf();
        final node = InterfaceIdentityOps.node(3);
        Test.equals(true, InterfaceIdentityOps.same(leaf, leaf));
        Test.equals(false, InterfaceIdentityOps.same(leaf, node));
        Test.equals(true, InterfaceIdentityOps.different(leaf, node));
        Test.equals(true, InterfaceIdentityOps.isSingleton(leaf));
        Test.equals(false, InterfaceIdentityOps.isSingleton(node));
        #else
        Test.equals(true, true);
        #end
    }
}
