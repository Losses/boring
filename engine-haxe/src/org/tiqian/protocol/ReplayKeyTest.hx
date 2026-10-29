package org.tiqian.protocol;

/**
 * Golden byte-exact vectors for the font-session replay keys (Stage2 protocol,
 * research 5.3). These strings are pinned identically to the Rust lane's
 * replay.rs tests: one bit of divergence would split every font-session cache
 * entry, so the vectors assert byte-for-byte (not "semantically equal").
 */
class ReplayKeyTest {
    @:test
    public static function shapeReplayKeysRenderByteIdentically():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ReplayKeyTest");
        recorder.section("shapeReplayKeysRenderByteIdentically");
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "[\"你好\",\"A\\u001fB\",400,false,\"zh-cn\",\"CjkText\",\"你好\"]",
            ReplayKey.renderShapeReplayKey(ReplayKey.shapeReplayKey("你好", ["A", "B"], 400.0, false, "zh-cn", "CjkText", "你好")));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "[\"x\",\"A\",700.5,true,\"en\",\"null\",\"y\"]",
            ReplayKey.renderShapeReplayKey(ReplayKey.shapeReplayKey("x", ["A"], 700.5, true, "en", null, "y")));
    }

    @:test
    public static function metricReplayKeysRenderByteIdentically():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ReplayKeyTest");
        recorder.section("metricReplayKeysRenderByteIdentically");
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "[\"A\\u001fB\",400,false,\"null\",\"B\"]",
            ReplayKey.renderMetricReplayKey(ReplayKey.metricReplayKey(["A", "B"], 400.0, false, null, "B")));
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "[\"A\",400,false,\"null\",\"null\"]",
            ReplayKey.renderMetricReplayKey(ReplayKey.metricReplayKey(["A"], 400.0, false, null, null)));
    }

    @:test
    public static function normalizedReplayNumbersCanonicalizeToTwelveDecimals():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ReplayKeyTest");
        recorder.section("normalizedReplayNumbersCanonicalizeToTwelveDecimals");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(1.0, ReplayKey.normalizedReplayNumber(16.0, 16.0), "16/16 -> 1.0");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(1.0, ReplayKey.normalizedReplayNumber(15.5, 15.5), "15.5/15.5 -> 1.0");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(1.0, ReplayKey.normalizedReplayNumber(3.3000000000000003, 3.3), "3.3000000000000003/3.3 -> 1.0");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(0.0, ReplayKey.normalizedReplayNumber(-0.0, 16.0), "-0.0/16 -> 0.0");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(null, ReplayKey.normalizedReplayNumber(Math.NaN, 16.0), "NaN -> null");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(null, ReplayKey.normalizedReplayNumber(Math.POSITIVE_INFINITY, 16.0), "INF -> null");
        org.tiqian.test.trace.TracedAssertions.assertEqualsNullableFloat(0.0, ReplayKey.normalizedReplayNumber(1e-13 * 16.0, 16.0), "1e-13*16/16 -> 0.0");
    }
}
