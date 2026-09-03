package haxe.crypto;

import haxe.Int64;
import haxe.io.Bytes;

/** Portable XXH64 implementation with an idempotent streaming digest. */
class Xxh64 {
	static function P1():Int64 return Int64.make(0x9E3779B1, 0x85EBCA87);
	static function P2():Int64 return Int64.make(0xC2B2AE3D, 0x27D4EB4F);
	static function P3():Int64 return Int64.make(0x165667B1, 0x9E3779F9);
	static function P4():Int64 return Int64.make(0x85EBCA77, 0xC2B2AE63);
	static function P5():Int64 return Int64.make(0x27D4EB2F, 0x165667C5);
	var seed:Int64;
	var v1:Int64;
	var v2:Int64;
	var v3:Int64;
	var v4:Int64;
	var mem:Array<Int>;
	var totalLen:Int64;
	var large:Bool;

	public function new(seed:Int64) {
		this.seed = seed;
		v1 = seed + P1() + P2(); v2 = seed + P2(); v3 = seed; v4 = seed - P1();
		mem = []; totalLen = Int64.ofInt(0); large = false;
	}

	public function update(data:Bytes):Void {
		totalLen += Int64.ofInt(data.length);
		var p = 0;
		if (mem.length + data.length < 32) { for (i in 0...data.length) mem.push(data.get(i)); return; }
		if (mem.length > 0) {
			while (mem.length < 32) mem.push(data.get(p++));
			consumeMem(); mem = []; large = true;
		}
		while (p <= data.length - 32) {
			v1 = round(v1, read(data,p)); v2 = round(v2, read(data,p+8));
			v3 = round(v3, read(data,p+16)); v4 = round(v4, read(data,p+24));
			p += 32; large = true;
		}
		while (p < data.length) mem.push(data.get(p++));
	}

	public function digest():Int64 {
		var h:Int64 = large ? largeStart() : seed + P5();
		h += totalLen;
		var p = 0;
		while (p <= mem.length - 8) { h ^= round(Int64.ofInt(0), readMem(p)); h = rotl(h,27) * P1() + P4(); p += 8; }
		if (p <= mem.length - 4) { h ^= Int64.ofInt(read32Mem(p)) * P1(); h = rotl(h,23) * P2() + P3(); p += 4; }
		while (p < mem.length) { h ^= Int64.ofInt(mem[p]) * P5(); h = rotl(h,11) * P1(); p++; }
		return avalanche(h);
	}

	function largeStart():Int64 {
		var h:Int64 = rotl(v1,1) + rotl(v2,7) + rotl(v3,12) + rotl(v4,18);
		h = merge(h,v1); h = merge(h,v2); h = merge(h,v3); h = merge(h,v4);
		return h;
	}

	function consumeMem():Void { v1=round(v1,readMem(0)); v2=round(v2,readMem(8)); v3=round(v3,readMem(16)); v4=round(v4,readMem(24)); }
	function readMem(p:Int):Int64 return Int64.make(read32Mem(p+4), read32Mem(p));
	function read32Mem(p:Int):Int return mem[p] | mem[p+1]<<8 | mem[p+2]<<16 | mem[p+3]<<24;
	public static function make(data:Bytes, seed:Int64):Int64 { var x=new Xxh64(seed); x.update(data); return x.digest(); }
	static function read(data:Bytes, p:Int):Int64 return Int64.make(read32(data,p+4), read32(data,p));
	static function read32(data:Bytes,p:Int):Int return data.get(p) | data.get(p+1)<<8 | data.get(p+2)<<16 | data.get(p+3)<<24;
	static function round(acc:Int64,input:Int64):Int64 { var x=acc+input*P2(); x=rotl(x,31); return x*P1(); }
	static function merge(acc:Int64,v:Int64):Int64 { var x=round(Int64.ofInt(0),v); return (acc^x)*P1()+P4(); }
	static function rotl(x:Int64,n:Int):Int64 return (x<<n)|(x >>> (64-n));
	static function avalanche(x:Int64):Int64 { var h=x; h^=h>>>33; h*=P2(); h^=h>>>29; h*=P3(); h^=h>>>32; return h; }
}
