package org.tiqian.protocol;

/**
 * The host layout request model, single-sourced in Haxe and generated for
 * TypeScript and Rust (Stage1-P5). The field set is the union of the two
 * handwritten copies it replaces: the Kotlin DTO lane
 * (ffi/js/src/jsMain/kotlin/org/tiqian/ffi/js/ParagraphWireCodec.kt,
 * PrepareParagraphRequestDto) and the Rust precompute lane
 * (platforms/web/server/precompute/engine/src/paragraph.rs:23-66,
 * ParagraphRequest). A consumer ignores the fields its lane does not use.
 * Validation lives in ParagraphRequestChecks; the domain issue names in
 * NamedError. The wire-parsing issue names of the separator
 * encoding (InvalidDecorationWire, InvalidTextSpanWire and friends) are
 * deliberately absent: they named the string packing, which does not
 * exist in the typed model.
 */
typedef ParagraphRequest = {
    var fontSessionId:String;
    var text:String;
    var maxWidthPx:Float;
    var fontFamilies:Array<String>;
    var fontSizePx:Float;
    var lineHeightPx:Float;
    var locale:String;
    var fontWeight:Int;
    var italic:Bool;
    var firstLineIndentIc:Float;
    var lineLengthGridEnabled:Bool;
    /** Absent reads as DEFAULT_EMPHASIS_DOT_GAP_EM (TextModel.kt:421 = 0.1). */
    var emphasisDotGapEm:Null<Float>;
    var sourceBoundaries:Array<Int>;
    var textSpans:Array<TextSpanInput>;
    var lineBreakSpans:Array<LineBreakSpanInput>;
    var inlineBoxes:Array<InlineBoxInput>;
    var inlineObjects:Array<InlineObjectInput>;
    var decorations:Array<DecorationInput>;
}
