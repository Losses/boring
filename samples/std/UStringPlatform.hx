package std;

/**
 * Cursor primitives the resident runtime.UString walks strings with
 * (docs/specs/stdlib/10-unicode-string-access.md). A cursor addresses the
 * storage the target actually iterates: UTF-16 unit indices on the script
 * targets and stage one, byte offsets on Rust. Every primitive is O(1) in
 * the cursor, so a full walk costs one pass whatever the storage is.
 *
 * Each target lowers these statics inline; no runtime module implements
 * them. Business code never calls them: it calls std.UString,
 * whose inline wrappers route into runtime.UString.
 */
extern class UStringPlatform {
    /** The cursor position one past the last character. */
    public static function end(s:String):Int;

    /** The code point that starts at `cursor`, which must sit on a boundary. */
    public static function codeAt(s:String, cursor:Int):Int;

    /** The cursor of the next character. */
    public static function advance(s:String, cursor:Int):Int;

    /** The substring between two boundary cursors, `start` no greater than `stop`. */
    public static function substringBetween(s:String, startCursor:Int, stopCursor:Int):String;

    /** The string holding one code point of the valid domain. */
    public static function fromCodePoint(code:Int):String;
}
