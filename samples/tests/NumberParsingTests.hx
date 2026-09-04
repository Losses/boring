package tests;

import boring.NumberParsingOps;
import std.Test;

class NumberParsingTests {
    @:test("parseFloat accepts complete decimal tokens")
    public static function floatSuccess():Void {
        Test.equals(1.0, NumberParsingOps.parseFloat("  +1.  "));
        Test.equals(0.5, NumberParsingOps.parseFloat(".5"));
        Test.equals(-125.0, NumberParsingOps.parseFloat("-1.25E+2"));
    }

    @:test("parseFloat rejects malformed and partial tokens as NaN")
    public static function floatFailure():Void {
        Test.equals(true, NumberParsingOps.failedFloat(""));
        Test.equals(true, NumberParsingOps.failedFloat("12x"));
        Test.equals(true, NumberParsingOps.failedFloat("1e"));
        Test.equals(true, NumberParsingOps.failedFloat("inf"));
        Test.equals(true, NumberParsingOps.failedFloat("Infinity"));
        Test.equals(true, NumberParsingOps.failedFloat("1f"));
        Test.equals(true, NumberParsingOps.failedFloat("0x10"));
        Test.equals(true, NumberParsingOps.failedFloat("\u0001 1.5"));
        Test.equals(true, NumberParsingOps.failedFloat("\u2028 1.5"));
        Test.equals(0.5, NumberParsingOps.parseFloat("\u000B.5"));
    }

    @:test("parseInt accepts decimal and hexadecimal tokens")
    public static function intSuccess():Void {
        Test.equals(-42, NumberParsingOps.parseInt(" -42 "));
        Test.equals(16, NumberParsingOps.parseInt("0x10"));
        Test.equals(31, NumberParsingOps.parseInt("0X1f"));
        Test.equals(12, NumberParsingOps.parseInt(" 12 "));
        Test.equals(26, NumberParsingOps.parseInt("+0X1a"));
        Test.equals(-42, NumberParsingOps.parseInt("\u000B-42"));
        Test.equals(-2147483648, NumberParsingOps.parseInt("-0x80000000"));
        Test.equals(-2147483648, NumberParsingOps.parseInt("-2147483648"));
        Test.equals(2147483647, NumberParsingOps.parseInt("0x7FFFFFFF"));
        Test.equals(2147483647, NumberParsingOps.parseInt("2147483647"));
    }

    @:test("parseInt rejects partial and overflowing tokens as null")
    public static function intFailure():Void {
        Test.equals(true, NumberParsingOps.failedInt("12x"));
        Test.equals(true, NumberParsingOps.failedInt("0x80000000"));
        Test.equals(true, NumberParsingOps.failedInt("0x"));
        Test.equals(true, NumberParsingOps.failedInt("2147483648"));
    }
}
