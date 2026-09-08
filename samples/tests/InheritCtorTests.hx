package tests;

import boring.InheritCtorOps;
import std.Test;

class InheritCtorTests {
    @:test("inherited data-class constructors preserve message values")
    public static function messageValue():Void {
        final value = new InheritCtorOps("inherited message");
        Test.equals("inherited message", value.message);
    }

    @:test("inherited data-class construction preserves the second message")
    public static function constructionAndCatch():Void {
        final value = new InheritCtorOps("caught message");
        Test.equals("caught message", value.message);
    }
}
