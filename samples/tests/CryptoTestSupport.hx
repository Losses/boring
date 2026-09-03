package tests;

import haxe.io.Bytes;

class CryptoTestSupport {
	public static function data(name:String):Bytes {
		if (name == "empty") return Bytes.alloc(0);
		if (name == "abc") return ascii([97, 98, 99]);
		if (name == "digits") return ascii([49, 50, 51, 52, 53, 54, 55, 56, 57]);
		var length = 0;
		if (name == "bytes0to255") length = 256;
		else if (name == "len1") length = 1;
		else if (name == "len16") length = 16;
		else if (name == "len17") length = 17;
		else if (name == "len63") length = 63;
		else if (name == "len64") length = 64;
		else if (name == "len65") length = 65;
		else if (name == "len127") length = 127;
		else if (name == "len128") length = 128;
		else if (name == "len129") length = 129;
		else if (name == "len239") length = 239;
		else if (name == "len240") length = 240;
		else if (name == "len241") length = 241;
		else if (name == "len1003") length = 1003;
		else if (name == "len1004") length = 1004;
		final bytes = Bytes.alloc(length);
		for (i in 0...length) bytes.set(i, name == "bytes0to255" ? i & 255 : (i * 31 + 7) & 255);
		return bytes;
	}

	static function ascii(values:Array<Int>):Bytes {
		final bytes = Bytes.alloc(values.length);
		for (i in 0...values.length) bytes.set(i, values[i]);
		return bytes;
	}

	public static function signed32(raw:Float):Int return raw >= 2147483648 ? Std.int(raw - 4294967296) : Std.int(raw);

	public static function i64Hex(value:haxe.Int64):String {
		return wordHex(haxe.Int64.getHigh(value)) + wordHex(haxe.Int64.getLow(value));
	}

	static function wordHex(value:Int):String {
		var s = StringTools.hex(value);
		while (s.length < 8) s = "0" + s;
		return s.toLowerCase();
	}
}
