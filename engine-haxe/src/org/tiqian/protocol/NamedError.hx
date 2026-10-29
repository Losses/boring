package org.tiqian.protocol;

/**
 * The NamedError family: the closed set of domain validation error names
 * shared by the Kotlin, Rust and TypeScript lanes (features/06-errors-and-
 * results.md:314, "a closed variant set defined once per domain and shared
 * by all four trees"). One variant per published issue name.
 *
 * The declaration order is the check order of the Rust port
 * (platforms/web/server/precompute/engine/src/paragraph.rs:74-131,
 * validate()); the five names only the Kotlin lane publishes
 * (ffi/js/src/jsMain/kotlin/org/tiqian/ffi/js/ParagraphWireCodec.kt) sit at
 * the Kotlin lane's check positions: InvalidEmphasisDotGapEm after
 * InvalidFontWeight, the three InvalidInlineObject* names after
 * InvalidInlineBoxGeometry and InvalidDecorationRange last. The three names
 * the TypeScript lane publishes (markdown-lowering.ts:778/:815,
 * lifecycle.ts:265, astro/integration.ts:110) are a subset of this set.
 *
 * Deliberately absent: the names of the packing mechanism. The
 * InvalidLayoutRequest* names (ffi/native/src/nativeMain/kotlin/org/tiqian/
 * ffi/cabi/LayoutRequestReader.kt:40-228) and the Invalid*Wire names
 * (ParagraphWireCodec.kt:56/71/106/124/136) named the request packing,
 * which the cutover deletes whole; the names die with it.
 */
enum NamedError {
    EmptyParagraph;
    InvalidMaximumMeasure;
    InvalidFontSize;
    InvalidLineHeight;
    InvalidFirstLineIndent;
    InvalidFontWeight;
    InvalidEmphasisDotGapEm;
    MissingExplicitFontFamilies;
    InvalidTextSpanRange;
    MissingTextSpanFontFamilies;
    InvalidTextSpanFontSize;
    InvalidTextSpanFontWeight;
    InvalidTextSpanBaselineShift;
    InvalidSourceBoundary;
    InvalidLineBreakSpanRange;
    InvalidInlineBoxRange;
    InvalidInlineBoxGeometry;
    InvalidInlineObjectRange;
    InvalidInlineObjectAdvance;
    InvalidInlineObjectVerticalGeometry;
    InvalidDecorationRange;
}
