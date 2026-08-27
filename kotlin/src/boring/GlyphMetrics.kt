package boring

/** Glyph bounding box in em units. */
class GlyphBounds(
    val xMin: Double,
    val yMin: Double,
    val xMax: Double,
    val yMax: Double
)

/** Fixed glyph metrics record shared by every language suite. */
class GlyphMetrics(
    val codePoint: Int,
    val advanceEm: Double,
    val bounds: GlyphBounds
)
