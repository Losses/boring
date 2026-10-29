package org.tiqian.protocol;

/**
 * Field and issue-name equality tests for the host request model
 * (Stage1-P5 acceptance). The issue names and their order pin the
 * handwritten lanes they replace: paragraph.rs:252-353 (unit tests) and
 * ParagraphWireCodec.kt:279-297. Whitespace edge cases cover U+00A0,
 * U+202F, U+3000, U+200B and the plain space, per the Kotlin
 * Character.isWhitespace ruling.
 */
class ParagraphRequestTest {
    @:test
    public static function validRequestPasses():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("validRequestPasses");
        ParagraphRequestChecks.validate(ParagraphRequestTestSupport.request());
        recorder.record("validate returned silently");
        org.tiqian.test.trace.TracedAssertions.assertTrue(true, "the plain request validates");
    }

    @:test
    public static function paragraphChecksReportTheDomainNamesInOrder():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("paragraphChecksReportTheDomainNamesInOrder");
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("EmptyParagraph", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withText("   ")));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("EmptyParagraph", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withText(std.UString.fromCodePoint(0x3000))));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidMaximumMeasure", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withMaxWidth(0.0)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidMaximumMeasure", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withMaxWidth(Math.NaN)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidFontSize", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withFontSize(-1.0)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidLineHeight", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withLineHeight(Math.POSITIVE_INFINITY)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidFirstLineIndent", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withIndent(Math.NaN)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidFontWeight", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withWeight(0)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidFontWeight", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withWeight(1001)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidEmphasisDotGapEm", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withGap(-0.1)));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("MissingExplicitFontFamilies", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withFamilies(["  "])));
    }

    @:test
    public static function absentGapAndNonBlankExoticSpacePass():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("absentGapAndNonBlankExoticSpacePass");
        ParagraphRequestChecks.validate(ParagraphRequestTestSupport.request());
        // U+00A0 is NOT Kotlin whitespace: a family made of it is non-blank
        // and the request validates (ParagraphWireCodec.kt:279 isNotBlank).
        final nbsp = ParagraphRequestTestSupport.withFamilies([std.UString.fromCodePoint(0x00A0)]);
        ParagraphRequestChecks.validate(nbsp);
        recorder.record("absent gap and U+00A0 family validated");
        org.tiqian.test.trace.TracedAssertions.assertTrue(true, "absent gap and U+00A0 family validate");
    }

    @:test
    public static function spanChecksCoverRangeFamiliesAndNumbers():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("spanChecksCoverRangeFamiliesAndNumbers");
        // Each assertion rebuilds the request and the span literal: the
        // Rust/Kotlin lanes clone the fixture into the request (value
        // semantics), so in-place span mutation would not reach the checks.
        final rangeBase = ParagraphRequestTestSupport.request();
        rangeBase.textSpans = [{ start: 2, end: 1, families: ["Fake CJK"], fontSizePx: 16.0, fontWeight: 400, italic: false, baselineShift: 0.0 }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidTextSpanRange", ParagraphRequestTestSupport.issueOf(rangeBase));
        final rangeBase2 = ParagraphRequestTestSupport.request();
        rangeBase2.textSpans = [{ start: 0, end: 9, families: ["Fake CJK"], fontSizePx: 16.0, fontWeight: 400, italic: false, baselineShift: 0.0 }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidTextSpanRange", ParagraphRequestTestSupport.issueOf(rangeBase2));
        final familiesBase = ParagraphRequestTestSupport.request();
        familiesBase.textSpans = [{ start: 0, end: 2, families: [" "], fontSizePx: 16.0, fontWeight: 400, italic: false, baselineShift: 0.0 }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("MissingTextSpanFontFamilies", ParagraphRequestTestSupport.issueOf(familiesBase));
        final zeroWidthBase = ParagraphRequestTestSupport.request();
        zeroWidthBase.textSpans = [{ start: 0, end: 2, families: [std.UString.fromCodePoint(0x200B)], fontSizePx: 16.0, fontWeight: 400, italic: false, baselineShift: 0.0 }];
        ParagraphRequestChecks.validate(zeroWidthBase);
        final fontSizeBase = ParagraphRequestTestSupport.request();
        fontSizeBase.textSpans = [{ start: 0, end: 2, families: ["Fake CJK"], fontSizePx: 0.0, fontWeight: 400, italic: false, baselineShift: 0.0 }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidTextSpanFontSize", ParagraphRequestTestSupport.issueOf(fontSizeBase));
        final weightBase = ParagraphRequestTestSupport.request();
        weightBase.textSpans = [{ start: 0, end: 2, families: ["Fake CJK"], fontSizePx: 16.0, fontWeight: 1001, italic: false, baselineShift: 0.0 }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidTextSpanFontWeight", ParagraphRequestTestSupport.issueOf(weightBase));
        final baselineBase = ParagraphRequestTestSupport.request();
        baselineBase.textSpans = [{ start: 0, end: 2, families: ["Fake CJK"], fontSizePx: 16.0, fontWeight: 400, italic: false, baselineShift: Math.NaN }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidTextSpanBaselineShift", ParagraphRequestTestSupport.issueOf(baselineBase));
    }

    @:test
    public static function boundariesAndRangesUseTheUtf16Length():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("boundariesAndRangesUseTheUtf16Length");
        // One astral character plus one BMP character: length 3 in UTF-16
        // units (stdlib/06-std-modules.md:318).
        final astral = ParagraphRequestTestSupport.withText(std.UString.fromCodePoint(0x1F600) + "字");
        astral.sourceBoundaries = [3];
        ParagraphRequestChecks.validate(astral);
        astral.sourceBoundaries = [4];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidSourceBoundary", ParagraphRequestTestSupport.issueOf(astral));
        final breaks = ParagraphRequestTestSupport.request();
        breaks.lineBreakSpans = [{ start: 0, end: 5, policy: "ProgressiveTechnical" }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidLineBreakSpanRange", ParagraphRequestTestSupport.issueOf(breaks));
        // Two independent fixtures: {2,3} is a legal range against the
        // 4-unit default text, so the range and geometry assertions must
        // not share one request (the range check runs first).
        final boxes = ParagraphRequestTestSupport.request();
        boxes.inlineBoxes = [{ start: 2, end: 5, inlineStart: 1.0, inlineEnd: 2.0, outerSpacing: "Narrow" }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidInlineBoxRange", ParagraphRequestTestSupport.issueOf(boxes));
        final geometry = ParagraphRequestTestSupport.request();
        geometry.inlineBoxes = [{ start: 0, end: 3, inlineStart: 1.0, inlineEnd: Math.NaN, outerSpacing: "Narrow" }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidInlineBoxGeometry", ParagraphRequestTestSupport.issueOf(geometry));
    }

    @:test
    public static function whitespaceEdgeSetMatchesTheKotlinLane():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("whitespaceEdgeSetMatchesTheKotlinLane");
        // Plain space and U+3000 ideographic space are Kotlin-whitespace.
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("EmptyParagraph", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withText(" ")));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("EmptyParagraph", ParagraphRequestTestSupport.issueOf(ParagraphRequestTestSupport.withText(std.UString.fromCodePoint(0x3000))));
        // U+00A0, U+202F and U+200B are not: the text is non-blank, so the
        // request validates (families stay intact).
        ParagraphRequestChecks.validate(ParagraphRequestTestSupport.withText(std.UString.fromCodePoint(0x00A0)));
        ParagraphRequestChecks.validate(ParagraphRequestTestSupport.withText(std.UString.fromCodePoint(0x202F)));
        ParagraphRequestChecks.validate(ParagraphRequestTestSupport.withText(std.UString.fromCodePoint(0x200B)));
        recorder.record("space/U+3000 blank; U+00A0/U+202F/U+200B non-blank");
        org.tiqian.test.trace.TracedAssertions.assertTrue(true, "the whitespace edge set matches Character.isWhitespace");
    }

    @:test
    public static function inlineObjectAndDecorationChecks():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ParagraphRequestTest");
        recorder.section("inlineObjectAndDecorationChecks");
        final objects = ParagraphRequestTestSupport.request();
        objects.inlineObjects = [{ start: 0, end: 9, advance: 1.0, ascent: 1.0, descent: 1.0 }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidInlineObjectRange", ParagraphRequestTestSupport.issueOf(objects));
        objects.inlineObjects[0].end = 2;
        objects.inlineObjects[0].advance = -1.0;
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidInlineObjectAdvance", ParagraphRequestTestSupport.issueOf(objects));
        objects.inlineObjects[0].advance = 1.0;
        objects.inlineObjects[0].ascent = Math.NaN;
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidInlineObjectVerticalGeometry", ParagraphRequestTestSupport.issueOf(objects));
        final decorations = ParagraphRequestTestSupport.request();
        decorations.decorations = [{ start: 3, end: 2, kind: "Underline" }];
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidDecorationRange", ParagraphRequestTestSupport.issueOf(decorations));
    }
}
