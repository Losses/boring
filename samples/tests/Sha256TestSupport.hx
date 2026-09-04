package tests;

import haxe.io.Bytes;

class Sha256TestSupport {
    public static function digestHex(value:Bytes):String {
        var result = "";
        for (i in 0...value.length) {
            final byte = value.get(i);
            final high = byte >>> 4;
            final low = byte & 15;
            result += String.fromCharCode(high < 10 ? 48 + high : 87 + high);
            result += String.fromCharCode(low < 10 ? 48 + low : 87 + low);
        }
        return result;
    }

    public static function zeroes(length:Int):Bytes
        return Bytes.alloc(length);
}
