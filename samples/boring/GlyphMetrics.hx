package boring;

/** Glyph bounding box in em units. */
typedef BoundsEm = {
    final xMin:Float;
    final yMin:Float;
    final xMax:Float;
    final yMax:Float;
}

/** Fixed glyph metrics record shared by every language suite. */
typedef GlyphMetrics = {
    final codePoint:Int;
    final advanceEm:Float;
    final bounds:BoundsEm;
}
