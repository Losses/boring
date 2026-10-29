package org.tiqian.protocol;

/**
 * The NamedError family's golden name list, kept out of the test class so
 * the test carries test members only (the interceptor rules shared logic to
 * an ordinary class). The goldens are the names the three lanes publish
 * today: the Rust port's check order (platforms/web/server/precompute/
 * engine/src/paragraph.rs:74-131) with the Kotlin lane's own names at their
 * check positions (ffi/js/src/jsMain/kotlin/org/tiqian/ffi/js/
 * ParagraphWireCodec.kt:279-297 and :48-144). The npm lane asserts the same
 * names (platforms/web/server/core/test/fonts.test.ts:105-108) and the Rust
 * unit tests pin them (paragraph.rs:261-280): this list is the three-lane
 * agreement point.
 */
class NamedErrorTestSupport {
    /**
     * The variant at the given declaration position, in statement switch
     * form because the guarded-source interceptor rewrites expression
     * switches. The rust target renders the exception payload enum without
     * the Copy derive, so the tests pass fresh constructor values instead
     * of moving them out of the variants vector index.
     */
    public static function variantAt(indexIdx:Int):NamedError {
        var v:NamedError;
        if (indexIdx == 0) v = EmptyParagraph;
        else if (indexIdx == 1) v = InvalidMaximumMeasure;
        else if (indexIdx == 2) v = InvalidFontSize;
        else if (indexIdx == 3) v = InvalidLineHeight;
        else if (indexIdx == 4) v = InvalidFirstLineIndent;
        else if (indexIdx == 5) v = InvalidFontWeight;
        else if (indexIdx == 6) v = InvalidEmphasisDotGapEm;
        else if (indexIdx == 7) v = MissingExplicitFontFamilies;
        else if (indexIdx == 8) v = InvalidTextSpanRange;
        else if (indexIdx == 9) v = MissingTextSpanFontFamilies;
        else if (indexIdx == 10) v = InvalidTextSpanFontSize;
        else if (indexIdx == 11) v = InvalidTextSpanFontWeight;
        else if (indexIdx == 12) v = InvalidTextSpanBaselineShift;
        else if (indexIdx == 13) v = InvalidSourceBoundary;
        else if (indexIdx == 14) v = InvalidLineBreakSpanRange;
        else if (indexIdx == 15) v = InvalidInlineBoxRange;
        else if (indexIdx == 16) v = InvalidInlineBoxGeometry;
        else if (indexIdx == 17) v = InvalidInlineObjectRange;
        else if (indexIdx == 18) v = InvalidInlineObjectAdvance;
        else if (indexIdx == 19) v = InvalidInlineObjectVerticalGeometry;
        else if (indexIdx == 20) v = InvalidDecorationRange;
        else v = InvalidDecorationRange;
        return v;
    }
    /** The published names in check order (authorities in the class header). */
    public static function golden():Array<String> {
        return [
            "EmptyParagraph",
            "InvalidMaximumMeasure",
            "InvalidFontSize",
            "InvalidLineHeight",
            "InvalidFirstLineIndent",
            "InvalidFontWeight",
            "InvalidEmphasisDotGapEm",
            "MissingExplicitFontFamilies",
            "InvalidTextSpanRange",
            "MissingTextSpanFontFamilies",
            "InvalidTextSpanFontSize",
            "InvalidTextSpanFontWeight",
            "InvalidTextSpanBaselineShift",
            "InvalidSourceBoundary",
            "InvalidLineBreakSpanRange",
            "InvalidInlineBoxRange",
            "InvalidInlineBoxGeometry",
            "InvalidInlineObjectRange",
            "InvalidInlineObjectAdvance",
            "InvalidInlineObjectVerticalGeometry",
            "InvalidDecorationRange"
        ];
    }
}
