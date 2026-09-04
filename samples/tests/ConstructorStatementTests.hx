package tests;

import boring.ConstructorStatementOps;
import std.Test;

class ConstructorStatementTests {
    @:test("constructor lowers array comprehension fill")
    public static function testComprehension():Void {
        final value = new ConstructorStatementOps(2, []);
        Test.equals(3, value.filled.length, "constructor fill length");
        Test.equals(0, value.filled[2], "constructor fill value");
    }

    @:test("constructor lowers pipeline call with block lambda")
    public static function testPipelineBlockLambda():Void {
        final value = new ConstructorStatementOps(0, [1, 4]);
        Test.equals(2, value.mapped.length, "constructor pipeline length");
        Test.equals(2, value.mapped[0], "constructor pipeline first");
        Test.equals(5, value.mapped[1], "constructor pipeline second");
    }
}
