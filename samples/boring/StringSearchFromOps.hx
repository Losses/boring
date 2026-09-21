package boring;

#if (kotlin_output || ts_output)
/**
    `String.indexOf(sub, from)` starts its scan at `from`, so a caller that
    resumes after one brace block reads the next block's delimiter from the
    start index. A lowering that drops `from` restarts at index 0 and reads
    the block the scan has already passed. (StringSearchFromIndex)
**/
class StringSearchFromOps {
    /**
        Two brace blocks, the shape a TeX pattern reader scans: it reads a
        block name, then resumes at the name to find that block's own
        delimiters. The opening braces sit at indices 9 and 29, and the
        closing braces at 15 and 37.
    **/
    public static function twoBlocks():String {
        return "\\patterns{\na1b\n}\n\\hyphenation{\ntable\n}";
    }

    /** Index of the first `sub` at or after `from`, or -1 when absent. */
    public static function findFrom(text:String, sub:String, from:Int):Int {
        return text.indexOf(sub, from);
    }

    /** Index of the last `sub` at or before `from`, or -1 when absent. */
    public static function findLastFrom(text:String, sub:String, from:Int):Int {
        return text.lastIndexOf(sub, from);
    }

    /**
        The text between the delimiters of the brace block that follows the
        `name` occurrence: the scan resumes after `name`, and the closing
        brace is read from the position after that block's own opening brace.
    **/
    public static function blockBody(text:String, name:String):String {
        final start = text.indexOf(name);
        final open = text.indexOf("{", start);
        final close = text.indexOf("}", open + 1);
        return text.substring(open + 1, close);
    }
}
#else
class StringSearchFromOps {}
#end
