package boring;

import std.Graphemes;
import std.StringBuf;
import std.UString;

/**
 * Operations over the grapheme tier of
 * docs/specs/stdlib/11-grapheme-clusters.md. Every operation routes
 * through std.Graphemes, so each side answers in user-perceived
 * characters; the code-point contrast goes through std.UString.
 */
class GraphemeOps {
	public static function graphemeCount(text:String):Int {
		return Graphemes.count(text);
	}

	public static function codePointCount(text:String):Int {
		return UString.count(text);
	}

	public static function clusterAt(text:String, index:Int):Null<String> {
		return Graphemes.at(text, index);
	}

	public static function clusterSlice(text:String, from:Int, to:Int):String {
		return Graphemes.slice(text, from, to);
	}

	public static function clampedSlice(text:String):String {
		return Graphemes.slice(text, -2, 99);
	}

	public static function partCount(text:String):Int {
		return Graphemes.parts(text).length;
	}

	public static function firstPart(text:String):String {
		return Graphemes.parts(text)[0];
	}

	public static function lastPart(text:String):String {
		final parts = Graphemes.parts(text);
		return parts[parts.length - 1];
	}

	public static function graphemeBoundaries(text:String):Array<Int> {
		return Graphemes.boundaries(text);
	}

	public static function joinedParts(text:String):String {
		final parts = Graphemes.parts(text);
		final buffer = new StringBuf();
		for (index in 0...parts.length) {
			buffer.add(parts[index]);
		}
		return buffer.toString();
	}
}
