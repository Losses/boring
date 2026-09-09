package boring;

import std.UString;

/**
    Coverage for the runtime symbols the TypeScript backend exports from its
    @runtime-import module (docs/specs/stdlib/05). On TypeScript the binary32
    float edges lower through haxe.io.FPHelper to unqualified runtime imports
    and the code-point helpers lower through std.UString to the resident UString
    class, so the runtime template must ship floatToI32 and i32ToFloat. Backends
    whose runtime lacks those conversions run the same bit patterns through the
    portable Fp32 tier instead.
**/
class RuntimeExportOps {
	/** The binary32 bit pattern of the value, the unsigned low 32 bits. */
	public static function floatToBits(value:Float):Int {
		#if ts_output
		return haxe.io.FPHelper.floatToI32(value);
		#else
		return Fp32.toBits(value);
		#end
	}

	/** The value whose binary32 bit pattern is the given low 32 bits. */
	public static function bitsToFloat(bits:Int):Float {
		#if ts_output
		return haxe.io.FPHelper.i32ToFloat(bits);
		#else
		return Fp32.fromBits(bits);
		#end
	}

	/** The 32-bit float edges are mutual inverses on a round number. */
	public static function roundTripFloat(value:Float):Float {
		#if ts_output
		return haxe.io.FPHelper.i32ToFloat(haxe.io.FPHelper.floatToI32(value));
		#else
		return Fp32.fromBits(Fp32.toBits(value));
		#end
	}

	/** The code-point count of an ASCII string. */
	public static function asciiCount():Int {
		return UString.count("tiqian");
	}

	/** A code point by ordinal, or null past the end. */
	public static function codeAt(text:String, index:Int):Null<Int> {
		return UString.at(text, index);
	}

	/** Re-encoding code points round-trips the string. */
	public static function codePointsRoundTrip(text:String):String {
		return UString.fromCodePoints(UString.toCodePoints(text));
	}
}
