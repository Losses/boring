package haxe.crypto;

import haxe.Int64;
import haxe.io.Bytes;

typedef Xxh128Hash = {high:Int64, low:Int64};

/** Portable one-shot XXH3 128-bit hash. */
class Xxh128 {
    static function p1():Int64
        return Int64.make(0x9E3779B1, 0x85EBCA87);

    static function p2():Int64
        return Int64.make(0xC2B2AE3D, 0x27D4EB4F);

    static function p3():Int64
        return Int64.make(0x165667B1, 0x9E3779F9);

    static function p4():Int64
        return Int64.make(0x85EBCA77, 0xC2B2AE63);

    static function p5():Int64
        return Int64.make(0x27D4EB2F, 0x165667C5);

    static function p32_1():Int64
        return Int64.make(0, 0x9E3779B1);

    static function p32_2():Int64
        return Int64.make(0, 0x85EBCA77);

    static function p32_3():Int64
        return Int64.make(0, 0xC2B2AE3D);

    static function mx1():Int64
        return Int64.make(0x16566791, 0x9E3779F9);

    static function mx2():Int64
        return Int64.make(0x9FB21C65, 0x1E98DF25);

    static final secret:Array<Int> = [
        0xb8, 0xfe, 0x6c, 0x39, 0x23, 0xa4, 0x4b, 0xbe, 0x7c, 0x01, 0x81, 0x2c, 0xf7, 0x21, 0xad, 0x1c, 0xde, 0xd4, 0x6d, 0xe9, 0x83, 0x90, 0x97, 0xdb, 0x72,
        0x40, 0xa4, 0xa4, 0xb7, 0xb3, 0x67, 0x1f, 0xcb, 0x79, 0xe6, 0x4e, 0xcc, 0xc0, 0xe5, 0x78, 0x82, 0x5a, 0xd0, 0x7d, 0xcc, 0xff, 0x72, 0x21, 0xb8, 0x08,
        0x46, 0x74, 0xf7, 0x43, 0x24, 0x8e, 0xe0, 0x35, 0x90, 0xe6, 0x81, 0x3a, 0x26, 0x4c, 0x3c, 0x28, 0x52, 0xbb, 0x91, 0xc3, 0x00, 0xcb, 0x88, 0xd0, 0x65,
        0x8b, 0x1b, 0x53, 0x2e, 0xa3, 0x71, 0x64, 0x48, 0x97, 0xa2, 0x0d, 0xf9, 0x4e, 0x38, 0x19, 0xef, 0x46, 0xa9, 0xde, 0xac, 0xd8, 0xa8, 0xfa, 0x76, 0x3f,
        0xe3, 0x9c, 0x34, 0x3f, 0xf9, 0xdc, 0xbb, 0xc7, 0xc7, 0x0b, 0x4f, 0x1d, 0x8a, 0x51, 0xe0, 0x4b, 0xcd, 0xb4, 0x59, 0x31, 0xc8, 0x9f, 0x7e, 0xc9, 0xd9,
        0x78, 0x73, 0x64, 0xea, 0xc5, 0xac, 0x83, 0x34, 0xd3, 0xeb, 0xc3, 0xc5, 0x81, 0xa0, 0xff, 0xfa, 0x13, 0x63, 0xeb, 0x17, 0x0d, 0xdd, 0x51, 0xb7, 0xf0,
        0xda, 0x49, 0xd3, 0x16, 0x55, 0x26, 0x29, 0xd4, 0x68, 0x9e, 0x2b, 0x16, 0xbe, 0x58, 0x7d, 0x47, 0xa1, 0xfc, 0x8f, 0xf8, 0xb8, 0xd1, 0x7a, 0xd0, 0x31,
        0xce, 0x45, 0xcb, 0x3a, 0x8f, 0x95, 0x16, 0x04, 0x28, 0xaf, 0xd7, 0xfb, 0xca, 0xbb, 0x4b, 0x40, 0x7e
    ];

    static function r32(b:Array<Int>, p:Int):Int
        return b[p] | b[p + 1] << 8 | b[p + 2] << 16 | b[p + 3] << 24;

    static function r64(b:Array<Int>, p:Int):Int64 {
        var hi = r32(b, p + 4);
        var lo = r32(b, p);
        return Int64.make(hi, lo);
    }

    static function rb(d:Bytes, p:Int):Int
        return d.get(p);

    static function rd(d:Bytes, p:Int):Int64 {
        var hi = rb(d, p + 4) | rb(d, p + 5) << 8 | rb(d, p + 6) << 16 | rb(d, p + 7) << 24;
        var lo = rb(d, p) | rb(d, p + 1) << 8 | rb(d, p + 2) << 16 | rb(d, p + 3) << 24;
        return Int64.make(hi, lo);
    }

    static function rotl(x:Int64, n:Int):Int64
        return (x << n) | (x >>> (64 - n));

    static function swap32(x:Int):Int
        return (x >>> 24) | ((x >>> 8) & 0xff00) | ((x << 8) & 0xff0000) | (x << 24);

    static function swap64(x:Int64):Int64 {
        var hi = swap32(Int64.getLow(x));
        var lo = swap32(Int64.getHigh(x));
        return Int64.make(hi, lo);
    }

    static function avalanche(x:Int64):Int64 {
        var h = x;
        h ^= h >>> 33;
        h *= p2();
        h ^= h >>> 29;
        h *= p3();
        return h ^ (h >>> 32);
    }

    static function fastAvalanche(x:Int64):Int64 {
        var h = x ^ (x >>> 37);
        h *= mx1();
        return h ^ (h >>> 32);
    }

    static function rrmxmx(x:Int64, len:Int64):Int64 {
        var h = x ^ rotl(x, 49) ^ rotl(x, 24);
        h *= mx2();
        h ^= (h >>> 35) + len;
        h *= mx2();
        return h ^ (h >>> 28);
    }

    static function carryOut(a:Int64, b:Int64, sum:Int64):Int64
        return (((a & b) | ((a | b) & ~sum)) < 0) ? Int64.make(0, 1) : Int64.make(0, 0);

    static function wideMul(a:Int64, b:Int64):Xxh128Hash {
        var aLo = Int64.make(0, Int64.getLow(a));
        var aHi = Int64.make(0, Int64.getHigh(a));
        var bLo = Int64.make(0, Int64.getLow(b));
        var bHi = Int64.make(0, Int64.getHigh(b));
        var p00 = aLo * bLo;
        var p01 = aLo * bHi;
        var p10 = aHi * bLo;
        var p11 = aHi * bHi;
        var t = p01 + p10;
        var c = carryOut(p01, p10, t);
        var ts = t << 32;
        var lo = p00 + ts;
        var c2 = carryOut(p00, ts, lo);
        var high = p11 + (t >>> 32) + (c << 32) + c2;
        return {high: high, low: lo};
    }

    static function mulXor(a:Int64, b:Int64):Int64 {
        var m = wideMul(a, b);
        return m.high ^ m.low;
    }

    static function mix16(d:Bytes, p:Int, s:Array<Int>, sp:Int, seed:Int64):Int64 {
        var x = rd(d, p) ^ (r64(s, sp) + seed);
        var y = rd(d, p + 8) ^ (r64(s, sp + 8) - seed);
        return mulXor(x, y);
    }

    static function mix32(a:Xxh128Hash, d:Bytes, p1i:Int, p2i:Int, s:Array<Int>, sp:Int, seed:Int64):Xxh128Hash {
        a.low += mix16(d, p1i, s, sp, seed);
        var x2 = rd(d, p2i) + rd(d, p2i + 8);
        a.low ^= x2;
        a.high += mix16(d, p2i, s, sp + 16, seed);
        var x1 = rd(d, p1i) + rd(d, p1i + 8);
        a.high ^= x1;
        return a;
    }

    static function short(d:Bytes, len:Int, s:Array<Int>, seed:Int64):Xxh128Hash {
        if (len > 8) {
            var bl = rd(d, 0) ^ rd(d, len - 8) ^ ((r64(s, 32) ^ r64(s, 40)) - seed);
            var m = wideMul(bl, p1());
            var lenM1 = Int64.ofInt(len - 1);
            m.low += lenM1 << 54;
            var ih = rd(d, len - 8) ^ ((r64(s, 48) ^ r64(s, 56)) + seed);
            m.high += ih + Int64.make(0, Int64.getLow(ih)) * Int64.make(0, 0x85EBCA76);
            m.low ^= swap64(m.high);
            var x = wideMul(m.low, p2());
            return {low: fastAvalanche(x.low), high: fastAvalanche(x.high + m.high * p2())};
        }
        if (len >= 4) {
            var seHi = Int64.getLow(seed) >>> 16;
            var seLo = Int64.getLow(seed) << 16;
            var se = seed ^ Int64.make(seHi, seLo);
            var bd = bytes(d);
            var inHi = r32(bd, 0);
            var inLo = r32(bd, len - 4);
            var inp = Int64.make(inHi, inLo);
            var sr = (r64(s, 16) ^ r64(s, 24)) + se;
            var len64 = Int64.ofInt(len);
            var m = wideMul(inp ^ sr, p1() + (len64 << 2));
            m.high += m.low << 1;
            m.low ^= m.high >>> 3;
            m.low ^= m.low >>> 35;
            m.low *= mx2();
            m.low ^= m.low >>> 28;
            m.high = fastAvalanche(m.high);
            return m;
        }
        if (len > 0) {
            var c1 = rb(d, 0);
            var c2 = rb(d, len >> 1);
            var c3 = rb(d, len - 1);
            var v = c1 << 16 | c2 << 24 | c3 | len << 8;
            var sv = swap32(v);
            var hLo = (sv << 13) | (sv >>> 19);
            var h = Int64.make(0, hLo);
            var lo = Int64.make(0, v);
            var k1Lo = r32(s, 0) ^ r32(s, 4);
            var k1 = Int64.make(0, k1Lo);
            var k2Lo = r32(s, 8) ^ r32(s, 12);
            var k2 = Int64.make(0, k2Lo);
            return {low: avalanche(lo ^ (k1 + seed)), high: avalanche(h ^ (k2 - seed))};
        }
        var zl = seed ^ (r64(s, 64) ^ r64(s, 72));
        var zh = seed ^ (r64(s, 80) ^ r64(s, 88));
        return {low: avalanche(zl), high: avalanche(zh)};
    }

    static function bytes(d:Bytes):Array<Int> {
        var a = [];
        var i = 0;
        while (i < d.length) {
            a.push(d.get(i));
            i++;
        }
        return a;
    }

    static function accumulate(a:Array<Int64>, d:Bytes, p:Int, s:Array<Int>, sp:Int):Void {
        var i = 0;
        while (i < 8) {
            var dv = rd(d, p + i * 8);
            var k = dv ^ r64(s, sp + i * 8);
            a[i ^ 1] += dv;
            var kLo = Int64.make(0, Int64.getLow(k));
            var kHi = Int64.make(0, Int64.getHigh(k));
            a[i] += kLo * kHi;
            i++;
        }
    }

    static function scramble(a:Array<Int64>, s:Array<Int>, sp:Int):Void {
        var i = 0;
        while (i < 8) {
            var x = a[i] ^ (a[i] >>> 47) ^ r64(s, sp + i * 8);
            a[i] = x * p32_1();
            i++;
        }
    }

    static function merge(a:Array<Int64>, s:Array<Int>, sp:Int, start:Int64):Int64 {
        var r = start;
        var i = 0;
        while (i < 4) {
            r += mulXor(a[i * 2] ^ r64(s, sp + i * 16), a[i * 2 + 1] ^ r64(s, sp + i * 16 + 8));
            i++;
        }
        return fastAvalanche(r);
    }

    static function custom(seed:Int64):Array<Int> {
        var out = [];
        var i = 0;
        while (i < 192) {
            out.push(0);
            i++;
        }
        var j = 0;
        while (j < 12) {
            write64(out, j * 16, r64(secret, j * 16) + seed);
            write64(out, j * 16 + 8, r64(secret, j * 16 + 8) - seed);
            j++;
        }
        return out;
    }

    static function write64(a:Array<Int>, p:Int, x:Int64):Void {
        var i = 0;
        while (i < 4) {
            a[p + i] = (Int64.getLow(x) >>> (i * 8)) & 255;
            i++;
        }
        var j = 0;
        while (j < 4) {
            a[p + j + 4] = (Int64.getHigh(x) >>> (j * 8)) & 255;
            j++;
        }
    }

    public static function make(d:Bytes, seed:Int64):Xxh128Hash {
        var len = d.length;
        var s = secret;
        if (len <= 16) {
            return short(d, len, s, seed);
        }
        if (len <= 128) {
            var len64 = Int64.ofInt(len);
            var zero = Int64.ofInt(0);
            var a:Xxh128Hash = {low: len64 * p1(), high: zero};
            var i = (len - 1) >> 5;
            while (i >= 0) {
                a = mix32(a, d, i * 16, len - 16 * (i + 1), s, i * 32, seed);
                i--;
            }
            var lo = fastAvalanche(a.low + a.high);
            var hi = zero - fastAvalanche(a.low * p1() + a.high * p4() + (len64 - seed) * p2());
            return {low: lo, high: hi};
        }
        if (len <= 240) {
            var len64 = Int64.ofInt(len);
            var zero = Int64.ofInt(0);
            var a:Xxh128Hash = {low: len64 * p1(), high: zero};
            var i = 32;
            while (i < 160) {
                a = mix32(a, d, i - 32, i - 16, s, i - 32, seed);
                i += 32;
            }
            a.low = fastAvalanche(a.low);
            a.high = fastAvalanche(a.high);
            var j = 160;
            while (j <= len) {
                a = mix32(a, d, j - 32, j - 16, s, 3 + j - 160, seed);
                j += 32;
            }
            a = mix32(a, d, len - 16, len - 32, s, 136 - 17 - 16, zero - seed);
            var lo = fastAvalanche(a.low + a.high);
            var hi = zero - fastAvalanche(a.low * p1() + a.high * p4() + (len64 - seed) * p2());
            return {low: lo, high: hi};
        }
        var ls = seed == Int64.ofInt(0) ? secret : custom(seed);
        var a = [p32_3(), p1(), p2(), p3(), p4(), p32_2(), p5(), p32_1()];
        var block = 64 * 16;
        var blocks = (len - 1) >> 10;
        var n = 0;
        while (n < blocks) {
            var j = 0;
            while (j < 16) {
                accumulate(a, d, n * block + j * 64, ls, j * 8);
                j++;
            }
            scramble(a, ls, 128);
            n++;
        }
        var stripes = ((len - 1) - block * blocks) >> 6;
        var j = 0;
        while (j < stripes) {
            accumulate(a, d, blocks * block + j * 64, ls, j * 8);
            j++;
        }
        accumulate(a, d, len - 64, ls, 192 - 64 - 7);
        var len64 = Int64.ofInt(len);
        return {low: merge(a, ls, 11, len64 * p1()), high: merge(a, ls, 192 - 64 - 11, ~(len64 * p2()))};
    }
}
