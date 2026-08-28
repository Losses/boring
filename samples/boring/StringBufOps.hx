package boring;

import std.StringBuf;

class StringBufOps {
	public static function buildEmpty():String {
		final buf = new StringBuf();
		return buf.toString();
	}

	public static function buildParts(a:String, b:String, c:String):String {
		final buf = new StringBuf();
		buf.add(a);
		buf.add(b);
		buf.add(c);
		return buf.toString();
	}

	public static function buildWithChars(prefix:String, codeA:Int, codeB:Int):String {
		final buf = new StringBuf();
		buf.add(prefix);
		buf.addChar(codeA);
		buf.addChar(codeB);
		return buf.toString();
	}

	public static function measureLength(parts:Array<String>):Int {
		final buf = new StringBuf();
		for (i in 0...parts.length) {
			buf.add(parts[i]);
		}
		return buf.length;
	}

	public static function buildIncremental():Array<String> {
		final buf = new StringBuf();
		buf.add("step1");
		final s1 = buf.toString();
		buf.add("-step2");
		final s2 = buf.toString();
		return [s1, s2];
	}
}
