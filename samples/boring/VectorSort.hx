package boring;

/**
 * Sort runtime per docs/specs/features/17-sorting.md. Codec code calls a
 * named strategy; comparator sorting stays banned everywhere else. The Haxe
 * body is the semantic reference; the TypeScript, Rust, and Kotlin bodies
 * are per-platform runtime code that must produce the identical output
 * array for the identical input.
 */
class VectorSort {
    /**
        Sorts records in place by code point, ascending, stable. Returns the
        same array.
    **/
    public static function byCodePoint(records:Array<GlyphMetrics>):Array<GlyphMetrics> {
        for (write in 1...records.length) {
            final record = records[write];
            final key = record.codePoint;
            var read = write - 1;
            while (read >= 0 && records[read].codePoint > key) {
                records[read + 1] = records[read];
                read -= 1;
            }
            records[read + 1] = record;
        }
        return records;
    }
}
