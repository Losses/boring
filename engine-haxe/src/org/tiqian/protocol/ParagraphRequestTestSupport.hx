package org.tiqian.protocol;

/** Test fixtures: one plain valid request and per-field mutations, plus the
 * issue-name probe that returns the thrown variant's published name. */
class ParagraphRequestTestSupport {
    public static function request():ParagraphRequest {
        return {
            fontSessionId: "tq-font-test-1",
            text: "正文一段",
            maxWidthPx: 80.0,
            fontFamilies: ["Fake CJK"],
            fontSizePx: 16.0,
            lineHeightPx: 24.0,
            locale: "zh-Hans",
            fontWeight: 400,
            italic: false,
            firstLineIndentIc: 0.0,
            lineLengthGridEnabled: false,
            emphasisDotGapEm: null,
            sourceBoundaries: [],
            textSpans: [],
            lineBreakSpans: [],
            inlineBoxes: [],
            inlineObjects: [],
            decorations: [],
        };
    }

    /** The published issue name of one caught variant. Kept local to the
     * test support so no target sees a call into the exception class,
     * which the Rust target does not land; the literals mirror
     * ParagraphRequestException.describe, the message function of
     * features/06. */
    public static function issueNameOf(error:NamedError):String {
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
    public static function issueOf(request:ParagraphRequest):String {
        var name = "";
        try {
            ParagraphRequestChecks.validate(request);
        } catch (error:ParagraphRequestException) {
            name = issueNameOf(error.error);
        }
        return name;
    }

    public static function withText(text:String):ParagraphRequest {
        final copy = request();
        copy.text = text;
        return copy;
    }

    public static function withMaxWidth(value:Float):ParagraphRequest {
        final copy = request();
        copy.maxWidthPx = value;
        return copy;
    }

    public static function withFontSize(value:Float):ParagraphRequest {
        final copy = request();
        copy.fontSizePx = value;
        return copy;
    }

    public static function withLineHeight(value:Float):ParagraphRequest {
        final copy = request();
        copy.lineHeightPx = value;
        return copy;
    }

    public static function withIndent(value:Float):ParagraphRequest {
        final copy = request();
        copy.firstLineIndentIc = value;
        return copy;
    }

    public static function withWeight(value:Int):ParagraphRequest {
        final copy = request();
        copy.fontWeight = value;
        return copy;
    }

    public static function withGap(value:Float):ParagraphRequest {
        final copy = request();
        copy.emphasisDotGapEm = value;
        return copy;
    }

    public static function withFamilies(families:Array<String>):ParagraphRequest {
        final copy = request();
        copy.fontFamilies = families;
        return copy;
    }
}
