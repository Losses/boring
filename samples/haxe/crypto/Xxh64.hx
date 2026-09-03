package haxe.crypto;

import haxe.Int64;
import haxe.io.Bytes;

/** Portable XXH64 implementation. */
class Xxh64 {
	static final P1 = Int64.make(0x9E3779B1, 0x85EBCA87);
	static final P2 = Int64.make(0xC2B2AE3D, 0x27D4EB4F);
	static final P3 = Int64.make(0x165667B1, 0x9E3779F9);
	static final P4 = Int64.make(0x85EBCA77, 0xC2B2AE63);
	static final P5 = Int64.make(0x27D4EB2F, 0x165667C5);
	var seed:Int64;
	var bytes:Array<Int>;
	public function new(seed:Int64) { this.seed = seed; bytes = []; }
	public function update(data:Bytes):Void for (i in 0...data.length) bytes.push(data.get(i));
	public function digest():Int64 {
		var input = Bytes.alloc(bytes.length);
		for (i in 0...bytes.length) input.set(i, bytes[i]);
		return make(input, seed);
	}
	public static function make(data:Bytes, seed:Int64):Int64 {
		var p = 0; var h:Int64;
		if (data.length >= 32) {
			var v1 = seed + P1 + P2; var v2 = seed + P2; var v3 = seed;
			var v4 = seed - P1;
			while (p <= data.length - 32) { v1 = round(v1, read(data,p)); p += 8; v2 = round(v2, read(data,p)); p += 8; v3 = round(v3, read(data,p)); p += 8; v4 = round(v4, read(data,p)); p += 8; }
			h = rotl(v1,1) + rotl(v2,7) + rotl(v3,12) + rotl(v4,18);
			h = merge(h,v1); h = merge(h,v2); h = merge(h,v3); h = merge(h,v4);
		} else h = seed + P5;
		h += Int64.ofInt(data.length);
		while (p <= data.length - 8) { h ^= round(Int64.ofInt(0), read(data,p)); h = rotl(h,27) * P1 + P4; p += 8; }
		if (p <= data.length - 4) { h ^= Int64.ofInt(read32(data,p)) * P1; h = rotl(h,23) * P2 + P3; p += 4; }
		while (p < data.length) { h ^= Int64.ofInt(data.get(p)) * P5; h = rotl(h,11) * P1; p++; }
		return avalanche(h);
	}
	static function read(data:Bytes, p:Int):Int64 { return Int64.make(read32(data,p+4), read32(data,p)); }
	static function read32(data:Bytes,p:Int):Int { return data.get(p) | data.get(p+1)<<8 | data.get(p+2)<<16 | data.get(p+3)<<24; }
	static function round(acc:Int64,input:Int64):Int64 { var x = acc + input * P2; x = rotl(x,31); return x * P1; }
	static function merge(acc:Int64,v:Int64):Int64 { var x = round(Int64.ofInt(0),v); return (acc ^ x) * P1 + P4; }
	static function rotl(x:Int64,n:Int):Int64 return (x << n) | (x >>> (64-n));
	static function avalanche(x:Int64):Int64 { var h=x; h ^= h >>> 33; h *= P2; h ^= h >>> 29; h *= P3; h ^= h >>> 32; return h; }
}
