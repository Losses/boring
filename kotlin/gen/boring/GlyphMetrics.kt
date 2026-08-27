package boring

data class BoundsEm(
    val xMax: Double,
    val xMin: Double,
    val yMax: Double,
    val yMin: Double
)

typealias GlyphBounds = BoundsEm

data class GlyphMetrics(
    val advanceEm: Double,
    val bounds: BoundsEm,
    val codePoint: Int
)
