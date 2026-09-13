package tests;

import boring.StringBufUnionOps;
import boring.VectorException;
import boring.VectorError;
import std.Test;

class StringBufUnionTests {
    @:test("the buffer addChar fault stays a union variant beside the vector throw")
    public static function testBuildCharChecked():Void {
        Test.equals("A", StringBufUnionOps.buildCharChecked(1));
    }

    @:test("the buffer add fault stays a union variant beside the vector throw")
    public static function testBuildChecked():Void {
        Test.equals("item", StringBufUnionOps.buildChecked(1));
    }

    @:test("the vector throw still arrives through the union")
    public static function testVectorFault():Void {
        final got = try {
            StringBufUnionOps.buildChecked(0);
            0;
        } catch (e:VectorException) {
            switch (e.error) {
                case BadMagic: 0;
                case CountOverflow: 0;
                case UnexpectedEof: 1;
                case TrailingBytes(_): 0;
            }
        };
        Test.equals(1, got);
    }
}