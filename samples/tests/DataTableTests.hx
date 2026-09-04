package tests;

import boring.ScriptEvidenceTable;
import boring.WordCharacterTable;
import boring.PayloadTextTable;
import std.Test;

/**
 * Tests for compile-time data tables (docs/specs/features/20-compile-time-data-tables.md).
 * Covers boundary values, gaps, and flag lookups for synthetic script and word tables,
 * plus the raw payload table roundtrip.
 */
class DataTableTests {
    @:test("script table first record hits")
    public static function testScriptFirstRecord():Void {
        Test.equals(1, ScriptEvidenceTable.classify(0x0020), "first record start hit");
        Test.equals(1, ScriptEvidenceTable.classify(0x0050), "first record interior hit");
        Test.equals(1, ScriptEvidenceTable.classify(0x007E), "first record end hit");
    }

    @:test("script table last record hits")
    public static function testScriptLastRecord():Void {
        Test.equals(23, ScriptEvidenceTable.classify(0x02FA00), "last record start hit");
        Test.equals(23, ScriptEvidenceTable.classify(0x02FA10), "last record interior hit");
        Test.equals(23, ScriptEvidenceTable.classify(0x02FA1F), "last record end hit");
    }

    @:test("script table boundary misses")
    public static function testScriptMisses():Void {
        Test.equals(0, ScriptEvidenceTable.classify(0x0000), "below first record miss");
        Test.equals(0, ScriptEvidenceTable.classify(0x001F), "immediately below first record miss");
        Test.equals(0, ScriptEvidenceTable.classify(0x007F), "in gap between records miss");
        Test.equals(0, ScriptEvidenceTable.classify(0x0080), "in gap between records miss");
        Test.equals(0, ScriptEvidenceTable.classify(0x009F), "immediately before second record miss");
        Test.equals(0, ScriptEvidenceTable.classify(0x02FA20), "immediately above last record miss");
        Test.equals(0, ScriptEvidenceTable.classify(0x10FFFF), "far above last record miss");
    }

    @:test("script table intermediate record classifications")
    public static function testScriptIntermediateRecords():Void {
        Test.equals(2, ScriptEvidenceTable.classify(0x0370), "Greek record start");
        Test.equals(3, ScriptEvidenceTable.classify(0x0400), "Cyrillic record start");
        Test.equals(21, ScriptEvidenceTable.classify(0x4E00), "CJK Unified Ideographs start");
        Test.equals(21, ScriptEvidenceTable.classify(0x7000), "CJK Unified Ideographs mid");
        Test.equals(21, ScriptEvidenceTable.classify(0x9FFF), "CJK Unified Ideographs end");
        Test.equals(22, ScriptEvidenceTable.classify(0xAC00), "Hangul Syllables start");
    }

    @:test("word character table first record hits")
    public static function testWordFirstRecord():Void {
        Test.equals(true, WordCharacterTable.contains(0x0030), "digit 0 start hit");
        Test.equals(true, WordCharacterTable.contains(0x0035), "digit 5 mid hit");
        Test.equals(true, WordCharacterTable.contains(0x0039), "digit 9 end hit");
    }

    @:test("word character table last record hits")
    public static function testWordLastRecord():Void {
        Test.equals(true, WordCharacterTable.contains(0x020000), "last record start hit");
        Test.equals(true, WordCharacterTable.contains(0x020010), "last record mid hit");
        Test.equals(true, WordCharacterTable.contains(0x02001F), "last record end hit");
    }

    @:test("word character table misses and gaps")
    public static function testWordMisses():Void {
        Test.equals(false, WordCharacterTable.contains(0x0000), "null byte miss");
        Test.equals(false, WordCharacterTable.contains(0x002F), "char before digits miss");
        Test.equals(false, WordCharacterTable.contains(0x003A), "char after digits miss");
        Test.equals(false, WordCharacterTable.contains(0x0040), "char before uppercase miss");
        Test.equals(false, WordCharacterTable.contains(0x0060), "char before lowercase miss");
        Test.equals(false, WordCharacterTable.contains(0x020020), "char above last record miss");
    }

    @:test("word character table singleton ranges")
    public static function testWordSingletons():Void {
        Test.equals(true, WordCharacterTable.contains(0x005F), "underscore singleton hit");
        Test.equals(false, WordCharacterTable.contains(0x005E), "before underscore miss");
        Test.equals(false, WordCharacterTable.contains(0x0060), "after underscore miss");
    }

    @:test("payload table unit count and edge units")
    public static function testPayloadUnits():Void {
        Test.equals(186, PayloadTextTable.unitCount(), "payload unit count");
        Test.equals(0x73, PayloadTextTable.unitAt(0), "first unit is s");
        Test.equals(0x0A, PayloadTextTable.unitAt(185), "last unit is line feed");
        Test.equals(0xE9, PayloadTextTable.unitAt(184), "latin small letter e with acute unit");
    }

    @:test("payload table decodes back to the file content")
    public static function testPayloadRoundtrip():Void {
        final expected = "synthetic payload for boring spec 20 raw payload tables"
            + "\n"
            + "second line with \"quotes\" and \\ backslash"
            + "\n"
            + "third line plain digits 0123456789"
            + "\n"
            + "final line with latin small letter e with acute café"
            + "\n";
        Test.equals(expected, PayloadTextTable.text(), "decoded payload equals file content");
    }
}
