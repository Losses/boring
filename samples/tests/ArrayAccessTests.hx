package tests;

import boring.ArrayAccessOps;
import std.Test;

class ArrayAccessTests {
    @:test("split results support written array access")
    public static function testWriteSplit():Void {
        Test.equals("x", ArrayAccessOps.writeSplit("a,b"));
    }

    @:test("split results support read array access")
    public static function testReadSplit():Void {
        Test.equals("a", ArrayAccessOps.readSplit("a,b"));
    }



    @:test("composite StringBuf part can read its first character")
    public static function testCompositePart():Void {
        Test.equals(65, ArrayAccessOps.compositeStringBufPart("A"));
    }

    @:test("simple StringBuf part can read its first character")
    public static function testSimplePart():Void {
        Test.equals(65, ArrayAccessOps.simpleStringBufPart("A"));
    }
}
