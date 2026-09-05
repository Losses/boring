package tests;

import boring.NoSuchElementFaultException;
import boring.NoSuchElementThrower;
import std.Test;

class NoSuchElementTests {
    @:test("a module-listed exception class that only a catch references stays emitted")
    public static function caught():Void {
        var text = "";
        try {
            NoSuchElementThrower.missing();
        } catch (error:NoSuchElementFaultException) {
            text = error.message;
        }
        Test.equals("no such element", text);
    }
}