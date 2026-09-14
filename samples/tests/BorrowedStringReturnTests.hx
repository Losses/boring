package tests;

import boring.BorrowedStringReturnOps;
import std.Test;

class BorrowedStringReturnTests {
    @:test("a borrowed String parameter returns through an owned abstract String")
    public static function requireText():Void {
        #if rust_output
        final id = BorrowedStringReturnOps.requireText("ok");
        Test.equals("ok", id.value);
        #end
    }
}
