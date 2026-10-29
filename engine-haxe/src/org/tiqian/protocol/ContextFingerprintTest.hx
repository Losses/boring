package org.tiqian.protocol;

/**
 * Golden byte-exact vectors for the context fingerprint (Stage2 protocol,
 * ADR 0052 parity oracle). Each vector is pinned identically to the Rust
 * lane's context.rs output: one bit of divergence would split every font-
 * session cache namespace, so the vectors assert byte-for-byte (not
 * "semantically equal"). The three goldens together also prove the two
 * reference properties -- a changed fontSizePx yields a different digest,
 * and an equal configuration yields an equal digest.
 */
class ContextFingerprintTest {
    @:test
    public static function emptyFaceSetGolden():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("emptyFaceSetGolden");
        final digest = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [], ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "c8767d59df53c8929c7caac8afd7ab84f6e7aa2dc0bfd37809b6fb67b20e6ca6",
            ContextFingerprintTestSupport.hexBytes(digest));
    }

    @:test
    public static function oneFaceGolden():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("oneFaceGolden");
        final digest = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [ContextFingerprintTestSupport.face()],
            ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "31ef79198777efe20c3b105d570b981bf6c836f0e5c400842e25ddf7c4cc2294",
            ContextFingerprintTestSupport.hexBytes(digest));
    }

    @:test
    public static function fontSizeChangeAltersTheFingerprint():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("fontSizeChangeAltersTheFingerprint");
        final digest = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typographyAt(19.0), [], ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            "daad02265747bd6052418b898d019a5c38834f37b9460913ae1cfe94edadec14",
            ContextFingerprintTestSupport.hexBytes(digest));
    }

    @:test
    public static function equalConfigurationIsStable():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("ContextFingerprintTest");
        recorder.section("equalConfigurationIsStable");
        final a = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [], ContextFingerprintTestSupport.harfbuzzVersion());
        final b = ContextFingerprint.contextFingerprint(
            ContextFingerprintTestSupport.typography(), [], ContextFingerprintTestSupport.harfbuzzVersion());
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(
            ContextFingerprintTestSupport.hexBytes(a), ContextFingerprintTestSupport.hexBytes(b));
    }
}
