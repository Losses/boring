package tests;

import boring.JvmFieldPrivateOps;
import std.Test;

class JvmFieldPrivateTests {
    @:test("static object fields render visibility-correct JvmField placement")
    public static function resolveTags():Void {
        Test.equals("2:1:3", JvmFieldPrivateOps.resolve());
    }
}
