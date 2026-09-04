package tests;

import boring.StringConvOps;
import std.Test;

class StringConvTests {
    @:test("StringTools.hex renders uppercase and optional padding")
    public static function testHex():Void {
        Test.equals("0", StringConvOps.hexZero());
        Test.equals("A", StringConvOps.hexTen());
        Test.equals("FF", StringConvOps.hexByte());
        Test.equals("9FFF", StringConvOps.hexCjk());
        Test.equals("A", StringConvOps.hexDigitsZero());
        Test.equals("000A", StringConvOps.hexPadded());
        Test.equals("9FFF", StringConvOps.hexWiderThanDigits());
        Test.equals("000A", StringConvOps.hexDynamic(10, 4));
        Test.equals("U+9fff", StringConvOps.hexLowercase());
    }

    @:test("String case conversions preserve the target-independent rows")
    public static function testCaseConversions():Void {
        Test.equals("tiqian", StringConvOps.lowerAscii());
        Test.equals("TIQIAN", StringConvOps.upperAscii());
        Test.equals("zh-cn", StringConvOps.lowerLanguageTag());
        Test.equals("ZH-CN", StringConvOps.upperLanguageTag());
        Test.equals("提椠排版", StringConvOps.lowerCjk());
        Test.equals("提椠排版", StringConvOps.upperCjk());
        Test.equals("tiqian", StringConvOps.lowerDynamic("TIQIAN"));
        Test.equals("TIQIAN", StringConvOps.upperDynamic("tiqian"));
    }
}
