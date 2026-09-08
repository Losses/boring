package tests;

import boring.ProbeChain;
import std.Test;

class ProbeChainTests {
    @:test("recursive class fields are boxed")
    public static function depth():Void {
        Test.equals(1, new ProbeChain(new ProbeChain(null, 1), 0).depth());
    }
}
