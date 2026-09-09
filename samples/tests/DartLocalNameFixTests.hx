package tests;

import boring.DartLocalNameFixOps;
import std.Test;

class DartLocalNameFixTests {
    @:test("local declarations avoid shadowing their initializer")
    public static function localShadow():Void {
        Test.equals("value!", DartLocalNameFixOps.localShadow());
    }
}
