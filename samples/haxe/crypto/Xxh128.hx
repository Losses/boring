package haxe.crypto;

import haxe.Int64;
import haxe.io.Bytes;

typedef Xxh128Hash = { high: Int64, low: Int64 };

/** Portable one-shot XXH3 128-bit hash. */
class Xxh128 {
	static function p1():Int64 return Int64.make(0x9E3779B1, 0x85EBCA87);
	static function p2():Int64 return Int64.make(0xC2B2AE3D, 0x27D4EB4F);
	static function p3():Int64 return Int64.make(0x165667B1, 0x9E3779F9);
	static function p4():Int64 return Int64.make(0x85EBCA77, 0xC2B2AE63);
	static function p5():Int64 return Int64.make(0x27D4EB2F, 0x165667C5);
	static function p32_1():Int64 return Int64.make(0, 0x9E3779B1);
	static function p32_2():Int64 return Int64.make(0, 0x85EBCA77);
	static function p32_3():Int64 return Int64.make(0, 0xC2B2AE3D);
	static function mx1():Int64 return Int64.make(0x16566791, 0x9E3779F9);
	static function mx2():Int64 return Int64.make(0x9FB21C65, 0x1E98DF25);
	static final secret:Array<Int> = [
		0xb8,0xfe,0x6c,0x39,0x23,0xa4,0x4b,0xbe,0x7c,0x01,0x81,0x2c,0xf7,0x21,0xad,0x1c,0xde,0xd4,0x6d,0xe9,0x83,0x90,0x97,0xdb,0x72,0x40,0xa4,0xa4,0xb7,0xb3,0x67,0x1f,
		0xcb,0x79,0xe6,0x4e,0xcc,0xc0,0xe5,0x78,0x82,0x5a,0xd0,0x7d,0xcc,0xff,0x72,0x21,0xb8,0x08,0x46,0x74,0xf7,0x43,0x24,0x8e,0xe0,0x35,0x90,0xe6,0x81,0x3a,0x26,0x4c,
		0x3c,0x28,0x52,0xbb,0x91,0xc3,0x00,0xcb,0x88,0xd0,0x65,0x8b,0x1b,0x53,0x2e,0xa3,0x71,0x64,0x48,0x97,0xa2,0x0d,0xf9,0x4e,0x38,0x19,0xef,0x46,0xa9,0xde,0xac,0xd8,
		0xa8,0xfa,0x76,0x3f,0xe3,0x9c,0x34,0x3f,0xf9,0xdc,0xbb,0xc7,0xc7,0x0b,0x4f,0x1d,0x8a,0x51,0xe0,0x4b,0xcd,0xb4,0x59,0x31,0xc8,0x9f,0x7e,0xc9,0xd9,0x78,0x73,0x64,
		0xea,0xc5,0xac,0x83,0x34,0xd3,0xeb,0xc3,0xc5,0x81,0xa0,0xff,0xfa,0x13,0x63,0xeb,0x17,0x0d,0xdd,0x51,0xb7,0xf0,0xda,0x49,0xd3,0x16,0x55,0x26,0x29,0xd4,0x68,0x9e,
		0x2b,0x16,0xbe,0x58,0x7d,0x47,0xa1,0xfc,0x8f,0xf8,0xb8,0xd1,0x7a,0xd0,0x31,0xce,0x45,0xcb,0x3a,0x8f,0x95,0x16,0x04,0x28,0xaf,0xd7,0xfb,0xca,0xbb,0x4b,0x40,0x7e
	];
	static function r32(b:Array<Int>, p:Int):Int return b[p] | b[p+1] << 8 | b[p+2] << 16 | b[p+3] << 24;
	static function r64(b:Array<Int>, p:Int):Int64 return Int64.make(r32(b,p+4), r32(b,p));
	static function rb(d:Bytes,p:Int):Int return d.get(p);
	static function rd(d:Bytes,p:Int):Int64 return Int64.make(rb(d,p+4)|rb(d,p+5)<<8|rb(d,p+6)<<16|rb(d,p+7)<<24, rb(d,p)|rb(d,p+1)<<8|rb(d,p+2)<<16|rb(d,p+3)<<24);
	static function rotl(x:Int64,n:Int):Int64 return (x << n) | (x >>> (64-n));
	static function swap32(x:Int):Int return (x >>> 24) | ((x >>> 8) & 0xff00) | ((x << 8) & 0xff0000) | (x << 24);
	static function swap64(x:Int64):Int64 return Int64.make(swap32(Int64.getLow(x)),swap32(Int64.getHigh(x)));
	static function avalanche(x:Int64):Int64 { var h=x; h ^= h>>>33; h*=p2(); h^=h>>>29; h*=p3(); return h^(h>>>32); }
	static function fastAvalanche(x:Int64):Int64 { var h=x^(x>>>37); h*=mx1(); return h^(h>>>32); }
	static function rrmxmx(x:Int64,len:Int64):Int64 { var h=x^rotl(x,49)^rotl(x,24); h*=mx2(); h^=(h>>>35)+len; h*=mx2(); return h^(h>>>28); }
	static function carryOut(a:Int64,b:Int64,sum:Int64):Int64 return (((a & b) | ((a | b) & ~sum)) < 0) ? Int64.make(0,1) : Int64.make(0,0);
	static function wideMul(a:Int64,b:Int64):Xxh128Hash {
		final aLo=Int64.make(0,Int64.getLow(a)); final aHi=Int64.make(0,Int64.getHigh(a));
		final bLo=Int64.make(0,Int64.getLow(b)); final bHi=Int64.make(0,Int64.getHigh(b));
		final p00=aLo*bLo; final p01=aLo*bHi; final p10=aHi*bLo; final p11=aHi*bHi;
		final t=p01+p10; final c=carryOut(p01,p10,t); final ts=t<<32; final lo=p00+ts; final c2=carryOut(p00,ts,lo);
		return {high:p11+(t>>>32)+(c<<32)+c2,low:lo};
	}
	static function fold(a:Int64,b:Int64):Int64 { final m=wideMul(a,b); return m.high ^ m.low; }
	static function mix16(d:Bytes,p:Int,s:Array<Int>,sp:Int,seed:Int64):Int64 return fold(rd(d,p)^(r64(s,sp)+seed),rd(d,p+8)^(r64(s,sp+8)-seed));
	static function mix32(a:Xxh128Hash,d:Bytes,p1i:Int,p2i:Int,s:Array<Int>,sp:Int,seed:Int64):Xxh128Hash { a.low+=mix16(d,p1i,s,sp,seed); a.low^=rd(d,p2i)+rd(d,p2i+8); a.high+=mix16(d,p2i,s,sp+16,seed); a.high^=rd(d,p1i)+rd(d,p1i+8); return a; }
	static function short(d:Bytes,len:Int,s:Array<Int>,seed:Int64):Xxh128Hash {
		if(len>8) { final bl=(rd(d,0)^rd(d,len-8)^(r64(s,32)^r64(s,40))-seed); var m=wideMul(bl,p1()); m.low+=Int64.ofInt(len-1)<<54; final ih=rd(d,len-8)^(r64(s,48)^r64(s,56))+seed; m.high+=ih+Int64.make(0,Int64.getLow(ih))*Int64.make(0,0x85EBCA76); m.low^=swap64(m.high); final x=wideMul(m.low,p2()); return {low:fastAvalanche(x.low),high:fastAvalanche(x.high+m.high*p2())}; }
		if(len>=4) { final se=seed^Int64.make(Int64.getLow(seed)>>>16,Int64.getLow(seed)<<16); final inp=Int64.make(r32(bytes(d),0),r32(bytes(d),len-4)); var m=wideMul(inp^(r64(s,16)^r64(s,24))+se,p1()+(Int64.ofInt(len)<<2)); m.high+=m.low<<1; m.low^=m.high>>>3; m.low^=m.low>>>35; m.low*=mx2(); m.low^=m.low>>>28; m.high=fastAvalanche(m.high); return m; }
		if(len>0) { final c1=rb(d,0),c2=rb(d,len>>1),c3=rb(d,len-1); final v=c1<<16|c2<<24|c3|len<<8; final h=Int64.make(0,(swap32(v)<<13)|(swap32(v)>>>19)); final lo=Int64.make(0,v); return {low:avalanche(lo^(Int64.make(0,r32(s,0)^r32(s,4))+seed)),high:avalanche(h^(Int64.make(0,r32(s,8)^r32(s,12))-seed))}; }
		return {low:avalanche(seed^(r64(s,64)^r64(s,72))),high:avalanche(seed^(r64(s,80)^r64(s,88)))};
	}
	static function bytes(d:Bytes):Array<Int> { final a=[]; for(i in 0...d.length) a.push(d.get(i)); return a; }
	static function accumulate(a:Array<Int64>,d:Bytes,p:Int,s:Array<Int>,sp:Int):Void { for(i in 0...8) { final dv=rd(d,p+i*8); final k=dv^r64(s,sp+i*8); a[i^1]+=dv; a[i]+=Int64.make(0,Int64.getLow(k))*Int64.make(0,Int64.getHigh(k)); } }
	static function scramble(a:Array<Int64>,s:Array<Int>,sp:Int):Void { for(i in 0...8) { var x=a[i]^(a[i]>>>47)^r64(s,sp+i*8); a[i]=x*p32_1(); } }
	static function merge(a:Array<Int64>,s:Array<Int>,sp:Int,start:Int64):Int64 { var r=start; for(i in 0...4) r+=fold(a[i*2]^r64(s,sp+i*16),a[i*2+1]^r64(s,sp+i*16+8)); return fastAvalanche(r); }
	static function custom(seed:Int64):Array<Int> { final out=[]; for(i in 0...192) out.push(0); for(i in 0...12) { write64(out,i*16,r64(secret,i*16)+seed); write64(out,i*16+8,r64(secret,i*16+8)-seed); } return out; }
	static function write64(a:Array<Int>,p:Int,x:Int64):Void { for(i in 0...4) a[p+i]=(Int64.getLow(x) >>> (i*8)) & 255; for(i in 0...4) a[p+i+4]=(Int64.getHigh(x) >>> (i*8)) & 255; }
	public static function make(d:Bytes,seed:Int64):Xxh128Hash {
		final len=d.length; final s=secret;
		if(len<=16)return short(d,len,s,seed);
		if(len<=128) { var a:Xxh128Hash={low:Int64.ofInt(len)*p1(),high:Int64.ofInt(0)}; var i=Std.int((len-1)/32); while(i>=0){a=mix32(a,d,i*16,len-16*(i+1),s,i*32,seed);i--;} final lo=fastAvalanche(a.low+a.high); final hi=Int64.ofInt(0)-fastAvalanche(a.low*p1()+a.high*p4()+(Int64.ofInt(len)-seed)*p2()); return {low:lo,high:hi}; }
		if(len<=240) { var a:Xxh128Hash={low:Int64.ofInt(len)*p1(),high:Int64.ofInt(0)}; var i=32; while(i<160){a=mix32(a,d,i-32,i-16,s,i-32,seed);i+=32;} i=160; while(i<=len){a=mix32(a,d,i-32,i-16,s,3+i-160,seed);i+=32;} a=mix32(a,d,len-16,len-32,s,192-17-16,Int64.ofInt(0)-seed); return {low:fastAvalanche(a.low+a.high),high:Int64.ofInt(0)-fastAvalanche(a.low*p1()+a.high*p4()+(Int64.ofInt(len)-seed)*p2())}; }
		final ls=seed==Int64.ofInt(0)?secret:custom(seed); var a=[p32_3(),p1(),p2(),p3(),p4(),p32_2(),p5(),p32_1()]; final block=64*16; final blocks=Std.int((len-1)/block); var n=0; while(n<blocks){for(j in 0...16) accumulate(a,d,n*block+j*64,ls,j*8); scramble(a,ls,128);n++;} final stripes=Std.int(((len-1)-block*blocks)/64); for(j in 0...stripes) accumulate(a,d,blocks*block+j*64,ls,j*8); accumulate(a,d,len-64,ls,192-64-7); return {low:merge(a,ls,11,Int64.ofInt(len)*p1()),high:merge(a,ls,192-64-11,~(Int64.ofInt(len)*p2()))};
	}
}
