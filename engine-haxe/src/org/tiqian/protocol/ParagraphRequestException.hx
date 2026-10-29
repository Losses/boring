package org.tiqian.protocol;

/**
 * The exception class carries the enum instance (features/06:44-51) and its
 * static describe is the message function of features/06: the Rust target
 * lowers it into the Display impl of the payload enum inside the error
 * module (boring/reference/rust/gen/boring/vector_exception.rs) and the
 * TypeScript target keeps the class. Messages are display text derived
 * from the variant and no consumer reads them for identity
 * (features/06:397); the string of every variant is the published issue
 * name.
 */
class ParagraphRequestException extends haxe.Exception {
    public final error:NamedError;

    public function new(error:NamedError) {
        this.error = error;
        super(ParagraphRequestException.describe(error));
    }

    public static function describe(error:NamedError):String {
        return switch (error) {
            case EmptyParagraph: "EmptyParagraph";
            case InvalidMaximumMeasure: "InvalidMaximumMeasure";
            case InvalidFontSize: "InvalidFontSize";
            case InvalidLineHeight: "InvalidLineHeight";
            case InvalidFirstLineIndent: "InvalidFirstLineIndent";
            case InvalidFontWeight: "InvalidFontWeight";
            case InvalidEmphasisDotGapEm: "InvalidEmphasisDotGapEm";
            case MissingExplicitFontFamilies: "MissingExplicitFontFamilies";
            case InvalidTextSpanRange: "InvalidTextSpanRange";
            case MissingTextSpanFontFamilies: "MissingTextSpanFontFamilies";
            case InvalidTextSpanFontSize: "InvalidTextSpanFontSize";
            case InvalidTextSpanFontWeight: "InvalidTextSpanFontWeight";
            case InvalidTextSpanBaselineShift: "InvalidTextSpanBaselineShift";
            case InvalidSourceBoundary: "InvalidSourceBoundary";
            case InvalidLineBreakSpanRange: "InvalidLineBreakSpanRange";
            case InvalidInlineBoxRange: "InvalidInlineBoxRange";
            case InvalidInlineBoxGeometry: "InvalidInlineBoxGeometry";
            case InvalidInlineObjectRange: "InvalidInlineObjectRange";
            case InvalidInlineObjectAdvance: "InvalidInlineObjectAdvance";
            case InvalidInlineObjectVerticalGeometry: "InvalidInlineObjectVerticalGeometry";
            case InvalidDecorationRange: "InvalidDecorationRange";
        };
    }
}
