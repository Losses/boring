package tests;

import boring.StringUnitOps;
import std.Test;

class StringUnitTests {
    @:test("code-unit reads and splits follow the unit domain")
    public static function unitSurface():Void {
        Test.equals(46, StringUnitOps.codeInRange("a.b"));
        Test.equals(26912, StringUnitOps.codeInRange("提椠"));
        Test.equals(98, StringUnitOps.codeAtEnd("ab"));
        Test.equals(true, StringUnitOps.codeOutOfRange("ab") == null);
        Test.equals(true, StringUnitOps.isSpaceAt("a b", 1));
        Test.equals(false, StringUnitOps.isSpaceAt("a b", 99));
        Test.equals(-1, StringUnitOps.codeAtOrFallback("ab", 99));
        Test.equals(97, StringUnitOps.codeAtOrFallback("abc", 0));
        Test.equals(3, StringUnitOps.splitCount("1.0.0"));
        Test.equals("1", StringUnitOps.splitFirst("1.0.0"));
        Test.equals(3, StringUnitOps.splitEmptyParts("a....b"));
        Test.equals(1, StringUnitOps.splitAbsent("abc"));
        Test.equals("abc", "abcdef".substring(-2, 3));
        Test.equals("bcdef", "abcdef".substring(1, 99));
        Test.equals("bc", "abcdef".substring(3, 1));
        Test.equals("cdef", "abcdef".substring(2));
    }
}
