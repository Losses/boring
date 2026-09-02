package registry;

/** String helpers written on the primitive subset every target lowers:
 * substring, whole-element reads, and Int-typed locals. String.split
 * and charCodeAt stay out of the sources because the Rust mapping
 * passes the first through as a str iterator and reads the second as
 * raw bytes, so neither mixes with Int locals or substring offsets. */
class StringTools {
	public static function startsWith(s:String,p:String):Bool return s.substring(0,p.length)==p;
	public static function endsWith(s:String,p:String):Bool return p.length<=s.length && s.substring(s.length-p.length)==p;
	public static function has(a:Array<String>,x:String):Bool { for(i in 0...a.length) if(a[i]==x) return true; return false; }
	/** Characters of `s` as codes, one per character, the same domain
	 * substring addresses on every target. */
	public static function codes(s:String):Array<Int> { return std.UString.toCodePoints(s); }
	/** Number of characters in the domain codes() yields. */
	public static function countCodes(cs:Array<Int>):Int { var n:Int=0; for(i in 0...cs.length) n=n+1; return n; }
	public static function isSpaceCode(c:Int):Bool return c==32||c==9||c==10||c==13;
	/** Leading and trailing space characters removed, rebuilt through
	 * fromCodePoint so no code value crosses a function boundary. */
	public static function trim(s:String):String {
		var cs:Array<Int>=codes(s); var n:Int=countCodes(cs);
		var a:Int=0; var b:Int=n;
		while(a<b && isSpaceCode(cs[a])) a=a+1;
		while(b>a && isSpaceCode(cs[b-1])) b=b-1;
		var out=""; var i:Int=a;
		while(i<b) { out+=std.UString.fromCodePoint(cs[i]); i=i+1; }
		return out;
	}
	/** Splits `s` on the character whose code is `sep`, keeping empty
	 * parts, matching String.split semantics for the separator sets the
	 * tool accepts. */
	public static function splitCode(s:String, sep:Int):Array<String> {
		var cs:Array<Int>=codes(s);
		var out:Array<String>=[];
		var part="";
		for(i in 0...cs.length) {
			var c:Int=cs[i];
			if(c==sep) { out.push(part); part=""; }
			else part+=std.UString.fromCodePoint(c);
		}
		out.push(part);
		return out;
	}
	/** Position of the first `sep` in `cs`, or countCodes(cs) when the
	 * character is absent; callers compare against the count instead of
	 * a negative sentinel. */
	public static function codeBefore(cs:Array<Int>, sep:Int):Int {
		var n:Int=0;
		for(i in 0...cs.length) { if(cs[i]==sep) return n; n=n+1; }
		return n;
	}
	public static function indexOfCode(s:String, sep:Int):Int {
		var cs:Array<Int>=codes(s);
		for(i in 0...cs.length) if(cs[i]==sep) return i;
		return -1;
	}
}
