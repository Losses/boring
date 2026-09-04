package registry;

class Sha1 {
	public static function hex(text:String):String {
		var bytes:Array<Int> = utf8(text);
		var len = bytes.length;
		var size = ((len + 9 + 63) >> 6) << 6;
		var data:Array<Int> = [];
		var i = 0;
		while(i < size) { data.push(0); i = i + 1; }
		i = 0;
		while(i < len) { data[i] = bytes[i]; i = i + 1; }
		data[len] = 0x80;
		var bitLength = len * 8;
		i = 0;
		while(i < 8) { data[size - 1 - i] = i < 4 ? (bitLength >>> (i * 8)) & 255 : 0; i = i + 1; }
		var h0 = 0x67452301, h1 = 0xEFCDAB89, h2 = 0x98BADCFE, h3 = 0x10325476, h4 = 0xC3D2E1F0;
		var block = 0;
		while(block < (size >> 6)) {
			var w:Array<Int> = [];
			i = 0;
			while(i < 80) { w.push(0); i = i + 1; }
			i = 0;
			while(i < 16) { var j = (block * 64) + (i * 4); w[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | data[j + 3]; i = i + 1; }
			i = 16;
			while(i < 80) { w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1); i = i + 1; }
			var a = h0, b = h1, c = h2, d = h3, e = h4;
			i = 0;
			while(i < 80) {
				var f = i < 20 ? ((b & c) | ((b ^ -1) & d)) : i < 40 ? (b ^ c ^ d) : i < 60 ? ((b & c) | (b & d) | (c & d)) : (b ^ c ^ d);
				var k = i < 20 ? 0x5A827999 : i < 40 ? 0x6ED9EBA1 : i < 60 ? 0x8F1BBCDC : 0xCA62C1D6;
				var t = (rol(a, 5) + f + e + k + w[i]) | 0;
				e = d; d = c; c = rol(b, 30); b = a; a = t;
				i = i + 1;
			}
			h0 = (h0 + a) | 0; h1 = (h1 + b) | 0; h2 = (h2 + c) | 0; h3 = (h3 + d) | 0; h4 = (h4 + e) | 0;
			block = block + 1;
		}
		return word(h0) + word(h1) + word(h2) + word(h3) + word(h4);
	}
	static function utf8(text:String):Array<Int> {
		var out:Array<Int> = [];
		var i = 0;
		while(i < text.length) {
			var c = text.charCodeAt(i);
			i = i + 1;
			if(c < 0x80) out.push(c);
			else if(c < 0x800) { out.push(0xC0 | (c >> 6)); out.push(0x80 | (c & 63)); }
			else if(c >= 0xD800 && c <= 0xDBFF && i < text.length) {
				var c2 = text.charCodeAt(i);
				i = i + 1;
				var code = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
				out.push(0xF0 | (code >> 18)); out.push(0x80 | ((code >> 12) & 63)); out.push(0x80 | ((code >> 6) & 63)); out.push(0x80 | (code & 63));
			}
			else { out.push(0xE0 | (c >> 12)); out.push(0x80 | ((c >> 6) & 63)); out.push(0x80 | (c & 63)); }
		}
		return out;
	}
	static function rol(x:Int, n:Int):Int return (x << n) | (x >>> (32 - n));
	static function word(x:Int):String {
		var digits = "0123456789abcdef";
		var out = "";
		var s = 28;
		while(s >= 0) { out += digits.charAt((x >>> s) & 15); s = s - 4; }
		return out;
	}
}
