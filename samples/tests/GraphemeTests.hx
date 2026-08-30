package tests;

import boring.GraphemeOps;
import std.Test;
import std.UString;

class GraphemeTests {
	@:test("cjk text counts one cluster per character")
	public static function testCjkClusters():Void {
		Test.equals(4, GraphemeOps.graphemeCount("提椠排版"));
		Test.equals("提", GraphemeOps.clusterAt("提椠排版", 0));
		Test.equals("版", GraphemeOps.clusterAt("提椠排版", 3));
		Test.equals(null, GraphemeOps.clusterAt("提椠排版", 4));
	}

	@:test("combining marks join their base character")
	public static function testCombiningMarks():Void {
		final decomposed = UString.fromCodePoint(0x0065) + UString.fromCodePoint(0x0301);
		final precomposed = UString.fromCodePoint(0x00E9);
		Test.equals(1, GraphemeOps.graphemeCount(decomposed));
		Test.equals(1, GraphemeOps.graphemeCount(precomposed));
		Test.equals(2, GraphemeOps.codePointCount(decomposed));
		Test.equals(decomposed, GraphemeOps.clusterAt(decomposed, 0));
	}

	@:test("hangul jamo runs form one cluster")
	public static function testHangul():Void {
		final jamo = UString.fromCodePoint(0x1100) + UString.fromCodePoint(0x1161) + UString.fromCodePoint(0x11A8);
		final syllables = "한국어";
		Test.equals(1, GraphemeOps.graphemeCount(jamo));
		Test.equals(3, GraphemeOps.graphemeCount(syllables));
		Test.equals(3, GraphemeOps.codePointCount(jamo));
	}

	@:test("carriage return and line feed form one cluster")
	public static function testCrLf():Void {
		Test.equals(1, GraphemeOps.graphemeCount("\r\n"));
		Test.equals("\r\n", GraphemeOps.clusterAt("\r\n", 0));
		Test.equals(3, GraphemeOps.graphemeCount("a\r\nb"));
		Test.equals("\r\n", GraphemeOps.clusterAt("a\r\nb", 1));
		Test.equals("b", GraphemeOps.clusterAt("a\r\nb", 2));
	}

	@:test("emoji sequences with joiners and modifiers form one cluster")
	public static function testEmojiSequences():Void {
		final family = UString.fromCodePoint(0x1F468) + UString.fromCodePoint(0x200D) + UString.fromCodePoint(0x1F469) + UString.fromCodePoint(0x200D) + UString.fromCodePoint(0x1F467) + UString.fromCodePoint(0x200D) + UString.fromCodePoint(0x1F466);
		final thumbsUpWithTone = UString.fromCodePoint(0x1F44D) + UString.fromCodePoint(0x1F3FD);
		final keycap = UString.fromCodePoint(0x0031) + UString.fromCodePoint(0xFE0F) + UString.fromCodePoint(0x20E3);
		Test.equals(1, GraphemeOps.graphemeCount(family));
		Test.equals(7, GraphemeOps.codePointCount(family));
		Test.equals(1, GraphemeOps.graphemeCount(thumbsUpWithTone));
		Test.equals(2, GraphemeOps.codePointCount(thumbsUpWithTone));
		Test.equals(1, GraphemeOps.graphemeCount(keycap));
		Test.equals(family, GraphemeOps.clusterAt(family, 0));
		Test.equals(null, GraphemeOps.clusterAt(family, 1));
	}

	@:test("regional indicators pair up")
	public static function testRegionalIndicators():Void {
		final single = UString.fromCodePoint(0x1F1E8);
		final china = UString.fromCodePoint(0x1F1E8) + UString.fromCodePoint(0x1F1F3);
		final chinaJapan = UString.fromCodePoint(0x1F1E8) + UString.fromCodePoint(0x1F1F3) + UString.fromCodePoint(0x1F1EF) + UString.fromCodePoint(0x1F1F5);
		Test.equals(1, GraphemeOps.graphemeCount(single));
		Test.equals(1, GraphemeOps.graphemeCount(china));
		Test.equals(2, GraphemeOps.graphemeCount(chinaJapan));
		Test.equals(2, GraphemeOps.codePointCount(china));
		Test.equals(china, GraphemeOps.clusterAt(chinaJapan, 0));
	}

	@:test("devanagari conjuncts with a virama linker stay whole")
	public static function testDevanagariConjunct():Void {
		final conjunct = UString.fromCodePoint(0x0915) + UString.fromCodePoint(0x094D) + UString.fromCodePoint(0x0915);
		final withExtend = UString.fromCodePoint(0x0915) + UString.fromCodePoint(0x094D) + UString.fromCodePoint(0x0300) + UString.fromCodePoint(0x0915);
		final noSecondConsonant = UString.fromCodePoint(0x0915) + UString.fromCodePoint(0x094D) + UString.fromCodePoint(0x0020);
		Test.equals(1, GraphemeOps.graphemeCount(conjunct));
		Test.equals(3, GraphemeOps.codePointCount(conjunct));
		Test.equals(1, GraphemeOps.graphemeCount(withExtend));
		Test.equals(2, GraphemeOps.graphemeCount(noSecondConsonant));
	}

	@:test("prepend characters join the following cluster")
	public static function testPrepend():Void {
		final arabicNumberSign = UString.fromCodePoint(0x0600) + UString.fromCodePoint(0x0031) + UString.fromCodePoint(0x0032);
		Test.equals(2, GraphemeOps.graphemeCount(arabicNumberSign));
		Test.equals(3, GraphemeOps.codePointCount(arabicNumberSign));
		Test.equals(UString.fromCodePoint(0x0600) + UString.fromCodePoint(0x0031), GraphemeOps.clusterAt(arabicNumberSign, 0));
	}

	@:test("cluster slicing clamps like the code-point tier")
	public static function testSlicing():Void {
		final mixed = UString.fromCodePoint(0x1F44D) + UString.fromCodePoint(0x1F3FD) + UString.fromCodePoint(0x63D0) + UString.fromCodePoint(0x6920);
		Test.equals(3, GraphemeOps.graphemeCount(mixed));
		Test.equals(UString.fromCodePoint(0x1F44D) + UString.fromCodePoint(0x1F3FD), GraphemeOps.clusterSlice(mixed, 0, 1));
		Test.equals("提椠", GraphemeOps.clusterSlice(mixed, 1, 3));
		Test.equals(mixed, GraphemeOps.clampedSlice(mixed));
		Test.equals("", GraphemeOps.clusterSlice(mixed, 2, 1));
	}

	@:test("parts enumerate every cluster and join back to the source")
	public static function testParts():Void {
		final mixed = UString.fromCodePoint(0x1F44D) + UString.fromCodePoint(0x1F3FD) + UString.fromCodePoint(0x63D5) + UString.fromCodePoint(0x6920);
		Test.equals(3, GraphemeOps.partCount(mixed));
		Test.equals(UString.fromCodePoint(0x1F44D) + UString.fromCodePoint(0x1F3FD), GraphemeOps.firstPart(mixed));
		Test.equals("椠", GraphemeOps.lastPart(mixed));
		Test.equals(mixed, GraphemeOps.joinedParts(mixed));
		Test.equals(0, GraphemeOps.partCount(""));
	}

	@:test("boundary offsets list every cluster edge in string units")
	public static function testBoundaries():Void {
		final mixed = UString.fromCodePoint(0x1F44D) + UString.fromCodePoint(0x1F3FD) + UString.fromCodePoint(0x63D0) + UString.fromCodePoint(0x0301);
		final mixedBoundaries = GraphemeOps.graphemeBoundaries(mixed);
		Test.equals(3, mixedBoundaries.length);
		Test.equals(0, mixedBoundaries[0]);
		Test.equals(4, mixedBoundaries[1]);
		Test.equals(6, mixedBoundaries[2]);
		final cjkBoundaries = GraphemeOps.graphemeBoundaries("提椠排版");
		Test.equals(5, cjkBoundaries.length);
		Test.equals(4, cjkBoundaries[4]);
		final prepend = UString.fromCodePoint(0x0600) + UString.fromCodePoint(0x0031) + UString.fromCodePoint(0x0032);
		final prependBoundaries = GraphemeOps.graphemeBoundaries(prepend);
		Test.equals(3, prependBoundaries.length);
		Test.equals(2, prependBoundaries[1]);
		Test.equals(3, prependBoundaries[2]);
		final pairBoundaries = GraphemeOps.graphemeBoundaries("\r\n");
		Test.equals(2, pairBoundaries.length);
		Test.equals(2, pairBoundaries[1]);
		final emptyBoundaries = GraphemeOps.graphemeBoundaries("");
		Test.equals(1, emptyBoundaries.length);
		Test.equals(0, emptyBoundaries[0]);
	}
}
