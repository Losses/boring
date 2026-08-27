package boring

/**
 * Sort runtime per docs/specs/features/17-sorting.md. Codec code calls a
 * named strategy; comparator sorting stays banned everywhere else. The Haxe
 * body is the semantic reference; the TypeScript, Rust, and Kotlin bodies
 * are per-platform runtime code that must produce the identical output
 * list for the identical input.
 */
object VectorSort {
    /**
     * Sorts records in place by code point, ascending, stable. Returns the
     * same list.
     */
    fun byCodePoint(records: MutableList<GlyphMetrics>): MutableList<GlyphMetrics> {
        records.sortBy { it.codePoint }
        return records
    }
}
