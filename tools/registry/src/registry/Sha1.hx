package registry;

import haxe.io.Bytes;

class Sha1 {
	public static function hex(text:String):String {
		final input = Bytes.ofString(text);
		final bitLength = input.length * 8;
		final size = ((input.length + 9 + 63) >> 6) << 6;
		final data = Bytes.alloc(size);
		for(i in 0...input.length) data.set(i, input.get(i));
		data.set(input.length, 0x80);
		for(i in 0...8) data.set(size - 1 - i, (bitLength >>> (i * 8)) & 255);
		var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
		for(block in 0...(size >> 6)) {
			final w = [for(i in 0...80) 0];
			for(i in 0...16) { final j=(block*64)+(i*4); w[i]=(data.get(j)<<24)|(data.get(j+1)<<16)|(data.get(j+2)<<8)|data.get(j+3); }
			for(i in 16...80) w[i] = rol(w[i-3] ^ w[i-8] ^ w[i-14] ^ w[i-16], 1);
			var a=h0, b=h1, c=h2, d=h3, e=h4;
			for(i in 0...80) {
				final f = i < 20 ? ((b & c) | (~b & d)) : i < 40 ? (b ^ c ^ d) : i < 60 ? ((b & c) | (b & d) | (c & d)) : (b ^ c ^ d);
				final k = i < 20 ? 0x5A827999 : i < 40 ? 0x6ED9EBA1 : i < 60 ? 0x8F1BBCDC : 0xCA62C1D6;
				final t = (rol(a,5) + f + e + k + w[i]); e=d; d=c; c=rol(b,30); b=a; a=t;
			}
			h0 += a; h1 += b; h2 += c; h3 += d; h4 += e;
		}
		return word(h0)+word(h1)+word(h2)+word(h3)+word(h4);
	}
	static function rol(x:Int, n:Int):Int return (x << n) | (x >>> (32-n));
	static function word(x:Int):String return StringTools.hex(x, 8).toLowerCase();
}
