package org.tiqian.protocol;

/**
 * Golden byte-exact vectors for the font-contract cache key (Stage2 protocol,
 * ADR 0050 parity oracle). Each vector is pinned identically to the Rust
 * lane's font_contract.rs tests: one bit of divergence would split every
 * font-contract dash retry, so the vectors assert byte-for-byte (not
 * "semantically equal"). Inputs are built as WireValue directly because the
 * protocol layer has no JSON parser; the js lane's JSON is mirrored value
 * for value.
 */
class FontContractTest {
    @:test
    public static function textWithoutADashReturnsNone():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("FontContractTest");
        recorder.section("textWithoutADashReturnsNone");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableString(null, FontContractTestSupport.run(WStr("p1"), WStr("正文段落"), WNull));
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableString(null, FontContractTestSupport.run(WStr("p1"), WStr("a—b"), WNull));
    }

    @:test
    public static function oneDashGroupProducesOneProbeSpan():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("FontContractTest");
        recorder.section("oneDashGroupProducesOneProbeSpan");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableString(
            "{\"key\":\"p1\",\"text\":\"——\",\"textSpans\":[{\"start\":0,\"end\":2,\"fontFamilies\":[\"Dela Gothic One\"],\"fontSizePx\":18,\"fontWeight\":400,\"italic\":false,\"baselineShiftPx\":0}]}",
            FontContractTestSupport.run(WStr("p1"), WStr("前——后——尾"), WNull));
    }

    @:test
    public static function twoStyledDashRunsGroupByStyle():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("FontContractTest");
        recorder.section("twoStyledDashRunsGroupByStyle");
        final spans:WireValue = WArr([
            WObj([{ name: "start", value: WNum(0.0) }, { name: "end", value: WNum(3.0) }, { name: "fontFamilies", value: WArr([WStr("F B")]) }]),
            WObj([{ name: "start", value: WNum(3.0) }, { name: "end", value: WNum(9.0) }, { name: "fontSizePx", value: WNum(22.0) }, { name: "italic", value: WBool(true) }]),
        ]);
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableString(
            "{\"key\":\"p1\",\"text\":\"——⸺——\",\"textSpans\":[{\"start\":0,\"end\":2,\"fontFamilies\":[\"F B\"],\"fontSizePx\":18,\"fontWeight\":400,\"italic\":false,\"baselineShiftPx\":0},{\"start\":2,\"end\":3,\"fontFamilies\":[\"Dela Gothic One\"],\"fontSizePx\":22,\"fontWeight\":400,\"italic\":true,\"baselineShiftPx\":0},{\"start\":3,\"end\":5,\"fontFamilies\":[\"Dela Gothic One\"],\"fontSizePx\":22,\"fontWeight\":400,\"italic\":true,\"baselineShiftPx\":0}]}",
            FontContractTestSupport.run(WStr("p1"), WStr("前——中⸺尾——末"), spans));
    }

    @:test
    public static function laterSpansWinAndLooseValuesCoerce():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("FontContractTest");
        recorder.section("laterSpansWinAndLooseValuesCoerce");
        final spans:WireValue = WArr([
            WObj([{ name: "start", value: WNum(0.0) }, { name: "end", value: WNum(2.0) }, { name: "fontSizePx", value: WNum(9.0) }]),
            WObj([{ name: "start", value: WNum(0.0) }, { name: "end", value: WNum(2.0) }, { name: "fontFamilies", value: WArr([WStr("A"), WStr("B")]) }, { name: "fontSizePx", value: WStr("20") }, { name: "fontWeight", value: WStr("500") }, { name: "baselineShiftPx", value: WStr("1.5") }]),
        ]);
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableString(
            "{\"key\":\"7\",\"text\":\"——\",\"textSpans\":[{\"start\":0,\"end\":2,\"fontFamilies\":[\"A\",\"B\"],\"fontSizePx\":20,\"fontWeight\":500,\"italic\":false,\"baselineShiftPx\":1.5}]}",
            FontContractTestSupport.run(WNum(7.0), WStr("——"), spans));
    }

    @:test
    public static function unsafeSpanRangesNeverOwnADash():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("FontContractTest");
        recorder.section("unsafeSpanRangesNeverOwnADash");
        final spans:WireValue = WArr([
            WObj([{ name: "start", value: WStr("0") }, { name: "end", value: WNum(2.0) }, { name: "fontFamilies", value: WArr([WStr("A")]) }]),
            WObj([{ name: "start", value: WNum(0.5) }, { name: "end", value: WNum(2.0) }, { name: "fontFamilies", value: WArr([WStr("B")]) }]),
            WObj([{ name: "end", value: WNum(2.0) }, { name: "fontFamilies", value: WArr([WStr("C")]) }]),
        ]);
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableString(
            "{\"key\":\"p1\",\"text\":\"——\",\"textSpans\":[{\"start\":0,\"end\":2,\"fontFamilies\":[\"Dela Gothic One\"],\"fontSizePx\":18,\"fontWeight\":400,\"italic\":false,\"baselineShiftPx\":0}]}",
            FontContractTestSupport.run(WStr("p1"), WStr("——"), spans));
    }

}
