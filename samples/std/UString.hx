package std;

/**
 * Code-point-addressed string access (docs/specs/stdlib/10-unicode-string-access.md).
 * The public functions are inline wrappers: the construction-domain checks
 * expand at each call site in the common layer, so the thrown
 * UStringException lowers through the normal per-target exception path, and
 * the unchecked primitives route into the runtime package through
 * std.UStringRT.
 */
class UString {
	public static inline function count(s:String):Int {
		return std.UStringRT.count(s);
	}

	public static inline function at(s:String, index:Int):Null<Int> {
		return std.UStringRT.at(s, index);
	}

	public static inline function slice(s:String, from:Int, to:Int):String {
		return std.UStringRT.slice(s, from, to);
	}

	public static inline function toCodePoints(s:String):Array<Int> {
		return std.UStringRT.toCodePoints(s);
	}

	public static inline function fromCodePoint(code:Int):String {
		if (code < 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
			throw new std.UStringException(std.UStringFault.InvalidCodePoint(code));
		}
		return std.UStringRT.fromCodePoint(code);
	}

	public static inline function fromCodePoints(codes:Array<Int>):String {
		for (i in 0...codes.length) {
			final code:Int = codes[i];
			if (code < 0 || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
				throw new std.UStringException(std.UStringFault.InvalidCodePoint(code));
			}
		}
		return std.UStringRT.fromCodePoints(codes);
	}
}
