package tests;

import boring.FloatLiteralOps;
import std.Test;

class FloatLiteralOpsTests {
    @:test("leading-dot float in argument position lowers")
    public static function testArgLeadingDot():Void {
        Test.equals(0.001, FloatLiteralOps.argLeadingDot());
        #if rust_output
        Test.equals(0.0, FloatLiteralOps.integerConstructorArgument());
        #end
    }

    @:test("negative leading-dot float in initializer position lowers")
    public static function testLocalLeadingDotNeg():Void {
        Test.equals(-0.1, FloatLiteralOps.localLeadingDotNeg());
    }

    @:test("small-magnitude leading-dot float in argument position lowers")
    public static function testArgSmall():Void {
        Test.equals(0.25, FloatLiteralOps.argSmall());
    }

    @:test("negative small-magnitude leading-dot float in initializer position lowers")
    public static function testLocalSmallNeg():Void {
        Test.equals(-0.5, FloatLiteralOps.localSmallNeg());
    }
}
