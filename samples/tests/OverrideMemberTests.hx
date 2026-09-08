package tests;

import boring.OverrideMemberOps;
import std.Test;

class OverrideMemberTests {
    @:test("a handwritten zero-argument hashCode is emitted as an Any override")
    public static function hashMember():Void {
        Test.equals(17, OverrideMemberOps.hash(17));
    }
    @:test("ordinary members remain ordinary")
    public static function ordinary():Void {
        Test.equals("ordinary", OverrideMemberOps.ordinary());
    }
    @:test("message payloads retain their value")
    public static function message():Void {
        Test.equals("payload", OverrideMemberOps.message("payload"));
    }
}
