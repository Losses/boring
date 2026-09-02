package haxe.crypto;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/** Portable SHA-256 implementation over byte sequences. */
class Sha256 {
	static inline var BLOCK_LENGTH:Int = 64;
	static inline var DIGEST_LENGTH:Int = 32;

	var state:Array<Int>;
	var block:Bytes;
	var blockPos:Int;
	var totalLength:Int;

	public function new() {
		state = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A, 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19];
		block = Bytes.alloc(BLOCK_LENGTH);
		blockPos = 0;
		totalLength = 0;
	}

	public function update(data:Bytes):Void {
		var sourcePos = 0;
		while (sourcePos < data.length) {
			block.set(blockPos, data.get(sourcePos));
			blockPos += 1;
			sourcePos += 1;
			totalLength += 1;
			if (blockPos == BLOCK_LENGTH) {
				processBlock(state, block);
				blockPos = 0;
			}
		}
	}

	public function digest():Bytes {
		var finalState:Array<Int> = [];
		for (i in 0...8) finalState.push(state[i]);
		var finalBlock = Bytes.alloc(BLOCK_LENGTH);
		for (i in 0...BLOCK_LENGTH) finalBlock.set(i, 0);
		for (i in 0...blockPos) finalBlock.set(i, block.get(i));
		finalBlock.set(blockPos, 0x80);
		var position = blockPos + 1;
		if (position > 56) {
			processBlock(finalState, finalBlock);
			for (i in 0...56) finalBlock.set(i, 0);
		} else {
			for (i in position...56) finalBlock.set(i, 0);
		}
		finalBlock.set(56, 0);
		finalBlock.set(57, 0);
		finalBlock.set(58, 0);
		finalBlock.set(59, 0);
		finalBlock.set(60, (totalLength >>> 21) & 0xFF);
		finalBlock.set(61, (totalLength >>> 13) & 0xFF);
		finalBlock.set(62, (totalLength >>> 5) & 0xFF);
		finalBlock.set(63, totalLength << 3);
		processBlock(finalState, finalBlock);

		var output = new BytesBuffer();
		for (i in 0...8) {
			output.addByte(finalState[i] >>> 24);
			output.addByte(finalState[i] >>> 16);
			output.addByte(finalState[i] >>> 8);
			output.addByte(finalState[i]);
		}
		return output.getBytes();
	}

	public static function make(data:Bytes):Bytes {
		var hash = new Sha256();
		hash.update(data);
		return hash.digest();
	}

	static function processBlock(hash:Array<Int>, input:Bytes):Void {
		var words:Array<Int> = [];
		for (i in 0...64) words.push(0);
		for (i in 0...16) {
			var offset = i * 4;
			words[i] = (input.get(offset) << 24) | (input.get(offset + 1) << 16) | (input.get(offset + 2) << 8) | input.get(offset + 3);
		}
		for (i in 16...64) words[i] = safeAdd(safeAdd(safeAdd(gamma1(words[i - 2]), words[i - 7]), gamma0(words[i - 15])), words[i - 16]);
		var a = hash[0]; var b = hash[1]; var c = hash[2]; var d = hash[3];
		var e = hash[4]; var f = hash[5]; var g = hash[6]; var h = hash[7];
		final k = [
			0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5, 0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
			0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174, 0xE49B69C1, 0xEFBE4786, 0xFC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
			0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967, 0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
			0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85, 0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
			0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3, 0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
			0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
		];
		for (i in 0...64) {
			var t1 = safeAdd(safeAdd(safeAdd(safeAdd(h, sigma1(e)), choose(e, f, g)), k[i]), words[i]);
			var t2 = safeAdd(sigma0(a), majority(a, b, c));
			h = g; g = f; f = e; e = safeAdd(d, t1); d = c; c = b; b = a; a = safeAdd(t1, t2);
		}
		hash[0] = safeAdd(hash[0], a); hash[1] = safeAdd(hash[1], b); hash[2] = safeAdd(hash[2], c); hash[3] = safeAdd(hash[3], d);
		hash[4] = safeAdd(hash[4], e); hash[5] = safeAdd(hash[5], f); hash[6] = safeAdd(hash[6], g); hash[7] = safeAdd(hash[7], h);
	}

	static function rotate(value:Int, distance:Int):Int return (value >>> distance) | (value << (32 - distance));
	static function choose(x:Int, y:Int, z:Int):Int return (x & y) ^ (~x & z);
	static function majority(x:Int, y:Int, z:Int):Int return (x & y) ^ (x & z) ^ (y & z);
	static function sigma0(x:Int):Int return rotate(x, 2) ^ rotate(x, 13) ^ rotate(x, 22);
	static function sigma1(x:Int):Int return rotate(x, 6) ^ rotate(x, 11) ^ rotate(x, 25);
	static function gamma0(x:Int):Int return rotate(x, 7) ^ rotate(x, 18) ^ (x >>> 3);
	static function gamma1(x:Int):Int return rotate(x, 17) ^ rotate(x, 19) ^ (x >>> 10);
	static function safeAdd(x:Int, y:Int):Int {
		var low = (x & 0xFFFF) + (y & 0xFFFF);
		var high = (x >> 16) + (y >> 16) + (low >> 16);
		return (high << 16) | (low & 0xFFFF);
	}
}
