package tests;

import std.Test;

#if (kotlin_output || ts_output)
import boring.StringSearchFromOps;
#end

/**
    A text of two brace blocks, the shape a TeX pattern reader scans: the
    scan reads a block name, then resumes at the name to find that block's
    own delimiters. (StringSearchFromIndex)
**/
class StringSearchFromTests {
    @:test("a string index search keeps its start index")
    public static function testFindFrom():Void {
        #if (kotlin_output || ts_output)
        final text = StringSearchFromOps.twoBlocks();
        // From 0 finds the first opening brace of the whole text.
        Test.equals(9, StringSearchFromOps.findFrom(text, "{", 0));
        // The start index is inclusive: a match sitting exactly at `from`
        // is still returned, so the scan never skips the named position.
        Test.equals(9, StringSearchFromOps.findFrom(text, "{", 9));
        // Resuming after the first block's brace reaches the second block.
        Test.equals(29, StringSearchFromOps.findFrom(text, "{", 10));
        // Past the end of the text, and an absent subject, report -1.
        Test.equals(-1, StringSearchFromOps.findFrom(text, "{", 100));
        Test.equals(-1, StringSearchFromOps.findFrom(text, "zzz", 0));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a resumed brace scan reads the second block")
    public static function testSecondBlock():Void {
        #if (kotlin_output || ts_output)
        final text = StringSearchFromOps.twoBlocks();
        Test.equals("\na1b\n", StringSearchFromOps.blockBody(text, "\\patterns"));
        Test.equals("\ntable\n", StringSearchFromOps.blockBody(text, "\\hyphenation"));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a backwards string search keeps the index it searches from")
    public static function testFindLastFrom():Void {
        #if (kotlin_output || ts_output)
        final text = StringSearchFromOps.twoBlocks();
        Test.equals(29, StringSearchFromOps.findLastFrom(text, "{", 29));
        Test.equals(9, StringSearchFromOps.findLastFrom(text, "{", 28));
        Test.equals(-1, StringSearchFromOps.findLastFrom(text, "zzz", 29));
        #else
        Test.equals(true, true);
        #end
    }
}
