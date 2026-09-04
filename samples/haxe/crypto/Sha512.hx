package haxe.crypto;

import haxe.Int64;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** Portable SHA-512 implementation over byte sequences. */
class Sha512 {
    static inline var BLOCK_LENGTH:Int = 128;

    var state:Array<Int64>;
    var block:Bytes;
    var blockPos:Int;
    var totalLength:Int64;

    public function new() {
        state = [
            Int64.make(0x6A09E667, 0xF3BCC908),
            Int64.make(0xBB67AE85, 0x84CAA73B),
            Int64.make(0x3C6EF372, 0xFE94F82B),
            Int64.make(0xA54FF53A, 0x5F1D36F1),
            Int64.make(0x510E527F, 0xADE682D1),
            Int64.make(0x9B05688C, 0x2B3E6C1F),
            Int64.make(0x1F83D9AB, 0xFB41BD6B),
            Int64.make(0x5BE0CD19, 0x137E2179)
        ];
        block = Bytes.alloc(BLOCK_LENGTH);
        blockPos = 0;
        totalLength = Int64.ofInt(0);
    }

    public function update(data:Bytes):Void {
        var sourcePos = 0;
        while (sourcePos < data.length) {
            block.set(blockPos, data.get(sourcePos));
            blockPos += 1;
            sourcePos += 1;
            totalLength = totalLength + 1;
            if (blockPos == BLOCK_LENGTH) {
                processBlock(state, block);
                blockPos = 0;
            }
        }
    }

    public function digest():Bytes {
        var finalState:Array<Int64> = [];
        for (i in 0...8)
            finalState.push(state[i]);
        var finalBlock = Bytes.alloc(BLOCK_LENGTH);
        for (i in 0...blockPos)
            finalBlock.set(i, block.get(i));
        finalBlock.set(blockPos, 0x80);
        var position = blockPos + 1;
        if (position > 112) {
            for (i in position...BLOCK_LENGTH)
                finalBlock.set(i, 0);
            processBlock(finalState, finalBlock);
            for (i in 0...BLOCK_LENGTH)
                finalBlock.set(i, 0);
        } else
            for (i in position...112)
                finalBlock.set(i, 0);
        for (i in 112...128)
            finalBlock.set(i, 0);
        var bitLength = totalLength << 3;
        for (i in 0...8)
            finalBlock.set(120 + i, Int64.getLow(bitLength >>> (56 - i * 8)));
        processBlock(finalState, finalBlock);
        var output = new BytesBuffer();
        for (i in 0...8) {
            var word = finalState[i];
            output.addByte(Int64.getLow(word >>> 56));
            output.addByte(Int64.getLow(word >>> 48));
            output.addByte(Int64.getLow(word >>> 40));
            output.addByte(Int64.getLow(word >>> 32));
            output.addByte(Int64.getLow(word >>> 24));
            output.addByte(Int64.getLow(word >>> 16));
            output.addByte(Int64.getLow(word >>> 8));
            output.addByte(Int64.getLow(word));
        }
        return output.getBytes();
    }

    public static function make(data:Bytes):Bytes {
        var hash = new Sha512();
        hash.update(data);
        return hash.digest();
    }

    static function processBlock(hash:Array<Int64>, input:Bytes):Void {
        var words:Array<Int64> = [];
        for (i in 0...80)
            words.push(Int64.ofInt(0));
        for (i in 0...16) {
            var offset = i * 8;
            words[i] = Int64.make((input.get(offset) << 24) | (input.get(offset + 1) << 16) | (input.get(offset + 2) << 8) | input.get(offset + 3),
                (input.get(offset + 4) << 24) | (input.get(offset + 5) << 16) | (input.get(offset + 6) << 8) | input.get(offset + 7));
        }
        for (i in 16...80) {
            final s1 = gamma1(words[i - 2]);
            final s0 = gamma0(words[i - 15]);
            words[i] = s1 + words[i - 7] + s0 + words[i - 16];
        }
        var a = hash[0], b = hash[1], c = hash[2], d = hash[3], e = hash[4], f = hash[5], g = hash[6], h = hash[7];
        final k:Array<Int64> = [
            Int64.make(0x428A2F98, 0xD728AE22),
            Int64.make(0x71374491, 0x23EF65CD),
            Int64.make(0xB5C0FBCF, 0xEC4D3B2F),
            Int64.make(0xE9B5DBA5, 0x8189DBBC),
            Int64.make(0x3956C25B, 0xF348B538),
            Int64.make(0x59F111F1, 0xB605D019),
            Int64.make(0x923F82A4, 0xAF194F9B),
            Int64.make(0xAB1C5ED5, 0xDA6D8118),
            Int64.make(0xD807AA98, 0xA3030242),
            Int64.make(0x12835B01, 0x45706FBE),
            Int64.make(0x243185BE, 0x4EE4B28C),
            Int64.make(0x550C7DC3, 0xD5FFB4E2),
            Int64.make(0x72BE5D74, 0xF27B896F),
            Int64.make(0x80DEB1FE, 0x3B1696B1),
            Int64.make(0x9BDC06A7, 0x25C71235),
            Int64.make(0xC19BF174, 0xCF692694),
            Int64.make(0xE49B69C1, 0x9EF14AD2),
            Int64.make(0xEFBE4786, 0x384F25E3),
            Int64.make(0x0FC19DC6, 0x8B8CD5B5),
            Int64.make(0x240CA1CC, 0x77AC9C65),
            Int64.make(0x2DE92C6F, 0x592B0275),
            Int64.make(0x4A7484AA, 0x6EA6E483),
            Int64.make(0x5CB0A9DC, 0xBD41FBD4),
            Int64.make(0x76F988DA, 0x831153B5),
            Int64.make(0x983E5152, 0xEE66DFAB),
            Int64.make(0xA831C66D, 0x2DB43210),
            Int64.make(0xB00327C8, 0x98FB213F),
            Int64.make(0xBF597FC7, 0xBEEF0EE4),
            Int64.make(0xC6E00BF3, 0x3DA88FC2),
            Int64.make(0xD5A79147, 0x930AA725),
            Int64.make(0x06CA6351, 0xE003826F),
            Int64.make(0x14292967, 0x0A0E6E70),
            Int64.make(0x27B70A85, 0x46D22FFC),
            Int64.make(0x2E1B2138, 0x5C26C926),
            Int64.make(0x4D2C6DFC, 0x5AC42AED),
            Int64.make(0x53380D13, 0x9D95B3DF),
            Int64.make(0x650A7354, 0x8BAF63DE),
            Int64.make(0x766A0ABB, 0x3C77B2A8),
            Int64.make(0x81C2C92E, 0x47EDAEE6),
            Int64.make(0x92722C85, 0x1482353B),
            Int64.make(0xA2BFE8A1, 0x4CF10364),
            Int64.make(0xA81A664B, 0xBC423001),
            Int64.make(0xC24B8B70, 0xD0F89791),
            Int64.make(0xC76C51A3, 0x0654BE30),
            Int64.make(0xD192E819, 0xD6EF5218),
            Int64.make(0xD6990624, 0x5565A910),
            Int64.make(0xF40E3585, 0x5771202A),
            Int64.make(0x106AA070, 0x32BBD1B8),
            Int64.make(0x19A4C116, 0xB8D2D0C8),
            Int64.make(0x1E376C08, 0x5141AB53),
            Int64.make(0x2748774C, 0xDF8EEB99),
            Int64.make(0x34B0BCB5, 0xE19B48A8),
            Int64.make(0x391C0CB3, 0xC5C95A63),
            Int64.make(0x4ED8AA4A, 0xE3418ACB),
            Int64.make(0x5B9CCA4F, 0x7763E373),
            Int64.make(0x682E6FF3, 0xD6B2B8A3),
            Int64.make(0x748F82EE, 0x5DEFB2FC),
            Int64.make(0x78A5636F, 0x43172F60),
            Int64.make(0x84C87814, 0xA1F0AB72),
            Int64.make(0x8CC70208, 0x1A6439EC),
            Int64.make(0x90BEFFFA, 0x23631E28),
            Int64.make(0xA4506CEB, 0xDE82BDE9),
            Int64.make(0xBEF9A3F7, 0xB2C67915),
            Int64.make(0xC67178F2, 0xE372532B),
            Int64.make(0xCA273ECE, 0xEA26619C),
            Int64.make(0xD186B8C7, 0x21C0C207),
            Int64.make(0xEADA7DD6, 0xCDE0EB1E),
            Int64.make(0xF57D4F7F, 0xEE6ED178),
            Int64.make(0x06F067AA, 0x72176FBA),
            Int64.make(0x0A637DC5, 0xA2C898A6),
            Int64.make(0x113F9804, 0xBEF90DAE),
            Int64.make(0x1B710B35, 0x131C471B),
            Int64.make(0x28DB77F5, 0x23047D84),
            Int64.make(0x32CAAB7B, 0x40C72493),
            Int64.make(0x3C9EBE0A, 0x15C9BEBC),
            Int64.make(0x431D67C4, 0x9C100D4C),
            Int64.make(0x4CC5D4BE, 0xCB3E42B6),
            Int64.make(0x597F299C, 0xFC657E2A),
            Int64.make(0x5FCB6FAB, 0x3AD6FAEC),
            Int64.make(0x6C44198C, 0x4A475817)
        ];
        for (i in 0...80) {
            var t1 = add4(h, sigma1(e), choose(e, f, g), add(k[i], words[i]));
            var t2 = add(sigma0(a), majority(a, b, c));
            h = g;
            g = f;
            f = e;
            e = add(d, t1);
            d = c;
            c = b;
            b = a;
            a = add(t1, t2);
        }
        hash[0] = add(hash[0], a);
        hash[1] = add(hash[1], b);
        hash[2] = add(hash[2], c);
        hash[3] = add(hash[3], d);
        hash[4] = add(hash[4], e);
        hash[5] = add(hash[5], f);
        hash[6] = add(hash[6], g);
        hash[7] = add(hash[7], h);
    }

    static function add(a:Int64, b:Int64):Int64
        return a + b;

    static function add4(a:Int64, b:Int64, c:Int64, d:Int64):Int64
        return a + b + c + d;

    static function choose(x:Int64, y:Int64, z:Int64):Int64
        return (x & y) ^ (~x & z);

    static function majority(x:Int64, y:Int64, z:Int64):Int64
        return (x & y) ^ (x & z) ^ (y & z);

    static function rotate(x:Int64, n:Int):Int64
        return (x >>> n) | (x << (64 - n));

    static function sigma0(x:Int64):Int64
        return rotate(x, 28) ^ rotate(x, 34) ^ rotate(x, 39);

    static function sigma1(x:Int64):Int64
        return rotate(x, 14) ^ rotate(x, 18) ^ rotate(x, 41);

    static function gamma0(x:Int64):Int64
        return rotate(x, 1) ^ rotate(x, 8) ^ (x >>> 7);

    static function gamma1(x:Int64):Int64
        return rotate(x, 19) ^ rotate(x, 61) ^ (x >>> 6);
}
