package tests;

import boring.SignedComparisonOps;
import std.Test;

class SignedComparisonTests {
    @:test("an ordered comparison with a signed index keeps the absent sentinel below a limit")
    public static function indexBelowLimit():Void {
        #if rust_output
        Test.equals(true, SignedComparisonOps.indexBelowLimit("abc", 1));
        Test.equals(true, SignedComparisonOps.indexBelowLimit("xbc", 1));
        Test.equals(false, SignedComparisonOps.indexBelowLimit("abxc", 1));
        #end
    }

    @:test("an ordered comparison with a signed index keeps the absent sentinel below an upper bound")
    public static function indexAtOrAboveLimit():Void {
        #if rust_output
        Test.equals(false, SignedComparisonOps.indexAtOrAboveLimit("abc", 1));
        Test.equals(true, SignedComparisonOps.indexAtOrAboveLimit("abxc", 1));
        #end
    }

    @:test("an equality comparison with a signed index compares the sentinel")
    public static function indexEqualsLimit():Void {
        #if rust_output
        Test.equals(false, SignedComparisonOps.indexEqualsLimit("abc", 1));
        Test.equals(true, SignedComparisonOps.indexEqualsLimit("abxc", 2));
        #end
    }
}
