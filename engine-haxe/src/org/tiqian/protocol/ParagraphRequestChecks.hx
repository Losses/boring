package org.tiqian.protocol;

/**
 * The domain validation of one host layout request. Checks run in the
 * documented order, so the first failure names the same issue on both
 * lanes (paragraph.rs:4-7); whitespace semantics are the Kotlin lane's
 * Character.isWhitespace set, written out in isKotlinWhitespace.
 */
class ParagraphRequestChecks {
    /** The Kotlin lane's default emphasis dot gap (TextModel.kt:421). */
    public static inline var DEFAULT_EMPHASIS_DOT_GAP_EM:Float = 0.1;

    /**
     * Runs every domain check in the documented order and throws the
     * ParagraphRequestException of the first failure. A request that comes
     * back silently satisfies both lanes' published contracts.
     */
    public static function validate(request:ParagraphRequest):Void {
        if (request.text.length == 0 || isBlankText(request.text)) {
            throw new ParagraphRequestException(EmptyParagraph);
        }
        if (!Math.isFinite(request.maxWidthPx) || request.maxWidthPx <= 0.0) {
            throw new ParagraphRequestException(InvalidMaximumMeasure);
        }
        if (!Math.isFinite(request.fontSizePx) || request.fontSizePx <= 0.0) {
            throw new ParagraphRequestException(InvalidFontSize);
        }
        if (!Math.isFinite(request.lineHeightPx) || request.lineHeightPx <= 0.0) {
            throw new ParagraphRequestException(InvalidLineHeight);
        }
        if (!Math.isFinite(request.firstLineIndentIc)) {
            throw new ParagraphRequestException(InvalidFirstLineIndent);
        }
        if (request.fontWeight < 1 || request.fontWeight > 1000) {
            throw new ParagraphRequestException(InvalidFontWeight);
        }
        // The field is bound to a local before the null test: the Kotlin
        // emitter's expression-if (KotlinExpr.hx:821) cannot smart-cast a
        // var class property, and a local val admits the cast (Stage1-P5b).
        final rawGapEm = request.emphasisDotGapEm;
        final gapEm = rawGapEm == null
            ? DEFAULT_EMPHASIS_DOT_GAP_EM
            : (rawGapEm : Float);
        if (!Math.isFinite(gapEm) || gapEm < 0.0) {
            throw new ParagraphRequestException(InvalidEmphasisDotGapEm);
        }
        if (!hasNonBlankFamily(request.fontFamilies)) {
            throw new ParagraphRequestException(MissingExplicitFontFamilies);
        }
        final textLength = request.text.length;
        var spanIndexIdx:Int = 0;
        while (spanIndexIdx < request.textSpans.length) {
            final span = request.textSpans[spanIndexIdx];
            if (!validRange(span.start, span.end, textLength)) {
                throw new ParagraphRequestException(InvalidTextSpanRange);
            }
            if (!hasNonBlankFamily(span.families)) {
                throw new ParagraphRequestException(MissingTextSpanFontFamilies);
            }
            if (!Math.isFinite(span.fontSizePx) || span.fontSizePx <= 0.0) {
                throw new ParagraphRequestException(InvalidTextSpanFontSize);
            }
            if (span.fontWeight < 1 || span.fontWeight > 1000) {
                throw new ParagraphRequestException(InvalidTextSpanFontWeight);
            }
            if (!Math.isFinite(span.baselineShift)) {
                throw new ParagraphRequestException(InvalidTextSpanBaselineShift);
            }
            spanIndexIdx++;
        }
        var boundaryIndexIdx:Int = 0;
        while (boundaryIndexIdx < request.sourceBoundaries.length) {
            final boundary = request.sourceBoundaries[boundaryIndexIdx];
            if (boundary < 0 || boundary > textLength) {
                throw new ParagraphRequestException(InvalidSourceBoundary);
            }
            boundaryIndexIdx++;
        }
        var breakIndexIdx:Int = 0;
        while (breakIndexIdx < request.lineBreakSpans.length) {
            final span = request.lineBreakSpans[breakIndexIdx];
            if (!validRange(span.start, span.end, textLength)) {
                throw new ParagraphRequestException(InvalidLineBreakSpanRange);
            }
            breakIndexIdx++;
        }
        var boxIndexIdx:Int = 0;
        while (boxIndexIdx < request.inlineBoxes.length) {
            final box = request.inlineBoxes[boxIndexIdx];
            if (!validRange(box.start, box.end, textLength)) {
                throw new ParagraphRequestException(InvalidInlineBoxRange);
            }
            if (!Math.isFinite(box.inlineStart) || !Math.isFinite(box.inlineEnd)) {
                throw new ParagraphRequestException(InvalidInlineBoxGeometry);
            }
            boxIndexIdx++;
        }
        var objectIndexIdx:Int = 0;
        while (objectIndexIdx < request.inlineObjects.length) {
            final object = request.inlineObjects[objectIndexIdx];
            if (!validRange(object.start, object.end, textLength)) {
                throw new ParagraphRequestException(InvalidInlineObjectRange);
            }
            if (!Math.isFinite(object.advance) || object.advance < 0.0) {
                throw new ParagraphRequestException(InvalidInlineObjectAdvance);
            }
            if (!Math.isFinite(object.ascent) || !Math.isFinite(object.descent)) {
                throw new ParagraphRequestException(InvalidInlineObjectVerticalGeometry);
            }
            objectIndexIdx++;
        }
        var decorationIndexIdx:Int = 0;
        while (decorationIndexIdx < request.decorations.length) {
            final decoration = request.decorations[decorationIndexIdx];
            if (!validRange(decoration.start, decoration.end, textLength)) {
                throw new ParagraphRequestException(InvalidDecorationRange);
            }
            decorationIndexIdx++;
        }
    }

    /** start in 0 until end, end within the UTF-16 length (paragraph.rs:209-211). */
    public static function validRange(start:Int, end:Int, textLength:Int):Bool {
        return start >= 0 && start < end && end <= textLength;
    }

    /**
     * The Kotlin Character.isWhitespace set, written out because the two
     * lanes' trim sets differ (paragraph.rs:73 versus
     * ParagraphWireCodec.kt:279). Excluded on purpose: U+00A0, U+2007 and
     * U+202F (non-breaking spaces) and U+200B (zero width space, format
     * category). Included: the C0 whitespace runs, space, NEL, OGHAM SPACE
     * MARK, the fixed-width spaces U+2000..U+200A, line and paragraph
     * separator, U+205F and the ideographic space U+3000. Surrogate units
     * (astral characters) are never whitespace.
     */
    public static function isKotlinWhitespace(code:Int):Bool {
        if (code >= 0x09 && code <= 0x0D) {
            return true;
        }
        if (code >= 0x1C && code <= 0x1F) {
            return true;
        }
        if (code == 0x20 || code == 0x85 || code == 0x1680) {
            return true;
        }
        if (code >= 0x2000 && code <= 0x200A) {
            return true;
        }
        return code == 0x2028 || code == 0x2029 || code == 0x205F || code == 0x3000;
    }

    /** Kotlin String.isBlank over UTF-16 units. */
    public static function isBlankText(text:String):Bool {
        var indexIdx:Int = 0;
        while (indexIdx < text.length) {
            final code = text.charCodeAt(indexIdx);
            if (code >= 0xD800 && code <= 0xDFFF) {
                return false;
            }
            if (!isKotlinWhitespace(code)) {
                return false;
            }
            indexIdx++;
        }
        return true;
    }

    /** Kotlin's blank-family drop (ParagraphWireCodec.kt:75, paragraph.rs:69-71). */
    public static function hasNonBlankFamily(families:Array<String>):Bool {
        var indexIdx:Int = 0;
        while (indexIdx < families.length) {
            if (!isBlankText(families[indexIdx])) {
                return true;
            }
            indexIdx++;
        }
        return false;
    }
}
