package tests;

import boring.PrivateClassOps;
import boring.PrivateClassPeerOps;
import std.Test;

class PrivateClassTests {
    @:test("file-private classes remain private and distinct")
    public static function distinctResolutions():Void {
        Test.equals("first", PrivateClassOps.resolve());
        Test.equals("second", PrivateClassPeerOps.resolve());
    }
}
