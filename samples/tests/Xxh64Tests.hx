package tests;

import haxe.Int64;
import haxe.crypto.Xxh64;
import haxe.io.Bytes;
import std.Test;

class Xxh64Tests {
    @:test("xxh64 vectors") public static function vectorTests():Void {
        final names = [
            "empty",
            "abc",
            "digits",
            "bytes0to255",
            "len1",
            "len16",
            "len17",
            "len63",
            "len64",
            "len65",
            "len127",
            "len128",
            "len129",
            "len239",
            "len240",
            "len241",
            "len1003",
            "len1004"
        ];
        final zeros = [
            "ef46db3751d8e999", "44bc2cf5ad770999", "8cb841db40e6ae83", "1facbe8406cd904b", "a96c7f0ce858bbb7", "a19ad429b02bc413", "fe9f0feb7eeedc09",
            "5c320a0d2707057f", "7bbabbc45729d17e", "f3980c34bae65dc1", "4822f4e67f60ea91", "725a5b9b3bedfe94", "28fc8362643627d7", "88fdd7285946d2b3",
            "d430520ae3ed2fc6", "d3f50496d5bf27e0", "6225f49abc0f2191", "c4d238ceb73c051c"
        ];
        final seeds = [
            "6ec6d05f61c7e7a7", "a7cb2aac405e36c7", "3005bb411ed586b8", "0b8d47fe1516af3e", "0c810166b30122a5", "0e3f56e88f759a50", "5006e8f2eec7efea",
            "355cc1872a486c6e", "ea2d5e8a98bec153", "e6f9eb9a843fa660", "009ef173a99f39eb", "40d43049ef11db9a", "63583bd491b95d3b", "66ff4a95ff37cf60",
            "f790e8a0c6467c05", "de6ba969db713bae", "bf845a9712242dfd", "5ffac0cf3e10779b"
        ];
        for (i in 0...names.length) {
            final data = CryptoTestSupport.data(names[i]);
            Test.equals(zeros[i], CryptoTestSupport.i64Hex(Xxh64.make(data, Int64.ofInt(0))));
            Test.equals(seeds[i], CryptoTestSupport.i64Hex(Xxh64.make(data, Int64.make(0x9E3779B1, 0x85EBCA87))));
        }
    }

    @:test("xxh64 streaming chunks") public static function streamingChunks():Void {
        final data = CryptoTestSupport.data("len240");
        for (step in [1, 3, 7, 31]) {
            final h = new Xxh64(Int64.make(0x9E3779B1, 0x85EBCA87));
            var p = 0;
            while (p < data.length) {
                final n = (step < data.length - p ? step : data.length - p);
                h.update(data.sub(p, n));
                p += n;
            }
            Test.equals(CryptoTestSupport.i64Hex(Xxh64.make(data, Int64.make(0x9E3779B1, 0x85EBCA87))), CryptoTestSupport.i64Hex(h.digest()));
        }
    }

    @:test("xxh64 digest remains usable") public static function digestIsIdempotent():Void {
        final h = new Xxh64(Int64.make(0x9E3779B1, 0x85EBCA87));
        h.update(CryptoTestSupport.data("len1"));
        final first = h.digest();
        Test.equals(CryptoTestSupport.i64Hex(first), CryptoTestSupport.i64Hex(h.digest()));
        h.update(CryptoTestSupport.data("len16"));
        Test.equals("03558a350cde4fc8", CryptoTestSupport.i64Hex(h.digest()));
    }
}
