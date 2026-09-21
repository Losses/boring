package tests;

import boring.StringUnitOps;
import std.Test;
import std.UString;

class StringUnitTests {
    @:test("code-unit reads and splits follow the unit domain")
    public static function unitSurface():Void {
        Test.equals(46, StringUnitOps.codeInRange("a.b"));
        Test.equals(26912, StringUnitOps.codeInRange("提椠"));
        Test.equals(98, StringUnitOps.codeAtEnd("ab"));
        Test.equals(true, StringUnitOps.codeOutOfRange("ab") == null);
        Test.equals(true, StringUnitOps.isSpaceAt("a b", 1));
        Test.equals(false, StringUnitOps.isSpaceAt("a b", 99));
        Test.equals(-1, StringUnitOps.codeAtOrFallback("ab", 99));
        Test.equals(97, StringUnitOps.codeAtOrFallback("abc", 0));
        Test.equals(3, StringUnitOps.splitCount("1.0.0"));
        Test.equals("1", StringUnitOps.splitFirst("1.0.0"));
        Test.equals(3, StringUnitOps.splitEmptyParts("a....b"));
        Test.equals(1, StringUnitOps.splitAbsent("abc"));
        Test.equals("abc", "abcdef".substring(-2, 3));
        Test.equals("bcdef", "abcdef".substring(1, 99));
        Test.equals("bc", "abcdef".substring(3, 1));
        Test.equals("cdef", "abcdef".substring(2));
    }

    // Spec 15 contracts charCodeAt over UTF-16 code units, so the two
    // units of a surrogate pair are separate addresses and neither one
    // is the code point. A receiver that walks code points answers the
    // code point at the pair's first index and misses the second unit.
    @:test("charCodeAt addresses UTF-16 code units")
    public static function charCodeAtUnitDomain():Void {
        Test.equals(97, StringUnitOps.codeAt("ab", 0));
        Test.equals(98, StringUnitOps.codeAt("ab", 1));
        Test.equals(true, StringUnitOps.codeAt("ab", 2) == null);

        final text = "a" + UString.fromCodePoint(0x1F600) + "b";
        Test.equals(97, StringUnitOps.codeAt(text, 0));
        Test.equals(0xD83D, StringUnitOps.codeAt(text, 1));
        Test.equals(0xDE00, StringUnitOps.codeAt(text, 2));
        Test.equals(98, StringUnitOps.codeAt(text, 3));
        Test.equals(true, StringUnitOps.codeAt(text, 4) == null);
    }

    // The same unit domain bounds substr: a position and a length count
    // UTF-16 units, so reading them as byte offsets cuts inside the
    // astral character and answers neither part.
    @:test("substr counts UTF-16 code units")
    public static function substrUnitDomain():Void {
        final astral = UString.fromCodePoint(0x1F600);
        final text = "a" + astral + "b";
        Test.equals("a", StringUnitOps.unitCut(text, 0, 1));
        Test.equals(astral, StringUnitOps.unitCut(text, 1, 2));
        Test.equals("b", StringUnitOps.unitCut(text, 3, 1));
        Test.equals("", StringUnitOps.unitCut(text, 4, 1));
        Test.equals(astral + "b", StringUnitOps.unitCutFrom(text, 1));
        Test.equals("b", StringUnitOps.unitCut(text, -1, 1));
    }

    // The empty delimiter is the one separator a platform split gets
    // wrong: Kotlin seeds a leading and a trailing empty part around the
    // units, so a guarded read downstream reaches an empty string.
    @:test("empty delimiter splits one part per code unit")
    public static function splitEmptyDelimiter():Void {
        final letters = StringUnitOps.splitUnits("abc");
        Test.equals(3, letters.length);
        Test.equals("a", letters[0]);
        Test.equals("b", letters[1]);
        Test.equals("c", letters[2]);

        Test.equals(3, StringUnitOps.splitUnitCount("abc"));
        Test.equals("a", StringUnitOps.splitUnitAt("abc", 0));
        Test.equals(0x61, StringUnitOps.splitUnitCode("abc", 0));

        Test.equals(1, StringUnitOps.splitUnits("5").length);
        Test.equals("5", StringUnitOps.splitUnits("5")[0]);
        Test.equals(1, StringUnitOps.splitUnitCount("5"));
        Test.equals("5", StringUnitOps.splitUnitAt("5", 0));
    }

    @:test("empty delimiter keeps a surrogate pair as two units")
    public static function splitEmptyDelimiterSurrogates():Void {
        final astral = UString.fromCodePoint(0x1F600);
        final text = "a" + astral + "b";
        // Spec 15 contracts s.length as the UTF-16 code unit count on every
        // target, so the astral pair counts as two units here too.
        Test.equals(4, text.length);

        final units = StringUnitOps.splitUnits(text);
        Test.equals(4, units.length);
        Test.equals("a", units[0]);
        Test.equals("b", units[3]);
        // Only targets whose string element type can hold a lone surrogate
        // keep the code unit itself; Rust and Swift replace it with U+FFFD
        // when the unit is materialized as a one-unit string.
        #if (kotlin_output || ts_output)
        Test.equals(0xD83D, StringUnitOps.splitUnitCode(text, 1));
        Test.equals(0xDE00, StringUnitOps.splitUnitCode(text, 2));
        #end
    }
}
