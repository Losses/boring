package tests;

import boring.UnderscoreParamOps;
import std.Test;

class UnderscoreParamTests {
    @:test("underscore parameters are readable and independently named")
    public static function underscoreParameters():Void {
        Test.equals(4, UnderscoreParamOps.resolve(3));
        Test.equals(7, UnderscoreParamOps.pair(3, 4));
    }
}
