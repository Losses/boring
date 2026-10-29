package org.tiqian.protocol;

/**
 * The canonical encoder's cross-language golden vectors (ADR 0052). The hex
 * strings are the same vectors the TypeScript lane asserts in
 * platforms/web/server/core/test/canonical.test.ts:16 ff. and the Rust lane
 * pins in its canonical.rs unit tests: the canonical bytes are the cache
 * identity, so one bit of divergence would split every cache entry.
 *
 * Assertions go through haxe.io.Bytes.toHex (stdlib/01-haxe-io-bytes.md
 * line 21); the digest golden pins haxe.crypto.Sha256.make against the
 * node:crypto value over vector0 (crypto/01-sha256-sha512.md lines 9-11).
 */
class CanonicalTest {
    @:test
    public static function goldenVectorsMatchTheSharedBytes():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("CanonicalTest");
        recorder.section("goldenVectorsMatchTheSharedBytes");
        CanonicalTestSupport.assertHex(recorder, "vector0", "54514353010006000000e4b8ade6968701000000000000624000000000000000000000000000000000",
            Canonical.encode(CanonicalTestSupport.WireObj("p-1", "中文", WNum(144)), Canonical.KIND_SNAPSHOT));
        CanonicalTestSupport.assertHex(recorder, "vector1", "54514353010106000000e4b8ade6968700000000000000000000000000000000",
            Canonical.encode(CanonicalTestSupport.WireObj("fc-1", "中文", null), Canonical.KIND_CONTRACT));
        CanonicalTestSupport.assertHex(recorder, "vector2", "5451435301000f000000e4b8ade69687e5ad97e68e92e7898801000000000000624002000000070100000000000000400100000000000010400100000061000000000000f03f010200000004000000687265661300000068747470733a2f2f6578616d706c652e636f6d05000000636c617373040000006c696e6b0401000000000000000001000000000000f03f02000000656d020000001f010000000000000000010000000000000040010000000f00000044656c6120476f74686963204f6e650000000000003240000000000000794001000000000000e0bf0101000000000000004001000000000000104000000000020000000701000000000000f03f0100000000000000400000000000002040000000000000104006000000536f757263650001000000000000084001000000000000104003000000000000000000000000000000000032400000000000004240",
            Canonical.encode(CanonicalTestSupport.FULL_VECTOR_INPUT(), Canonical.KIND_SNAPSHOT));
    }

    @:test
    public static function looseCoercionsCarryTheJsonLane():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("CanonicalTest");
        recorder.section("looseCoercionsCarryTheJsonLane");
        CanonicalTestSupport.assertHex(recorder, "vector3", "5451435301000800000020636f6572636520010000000000106240010000000501000000000000f03f010000000000000040010000006902130000005b5b2261222c2231225d2c5b2262222c325d5d010000000001000000000000000001000000000000f03f010000000401000000000000000001000000000000f03f01000000370200000000000000000008400000000000000000",
            Canonical.encode(CanonicalTestSupport.LOOSE_VECTOR_INPUT(), Canonical.KIND_SNAPSHOT));
    }

    @:test
    public static function nonArraySemanticsIsTheNamedIssue():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("CanonicalTest");
        recorder.section("nonArraySemanticsIsTheNamedIssue");
        final result = Canonical.encode(WObj([
            { name: "text", value: WStr("a") },
            { name: "semantics", value: WStr("no") },
        ]), Canonical.KIND_SNAPSHOT);
        switch (result) {
            case EncodeResult.CErr(issue):
                org.tiqian.test.trace.TracedAssertions.assertEqualsString("InvalidSnapshotSemantics", issue);
            case EncodeResult.COk(_):
                recorder.record("encode unexpectedly succeeded");
                org.tiqian.test.trace.TracedAssertions.assertTrue(false, "non-array semantics must be the named issue");
        }
    }

    @:test
    public static function nonFiniteAndMinusZeroCollapse():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("CanonicalTest");
        recorder.section("nonFiniteAndMinusZeroCollapse");
        final withoutWidth = Canonical.encode(WObj([
            { name: "text", value: WStr("a") },
        ]), Canonical.KIND_SNAPSHOT);
        final withNaN = Canonical.encode(WObj([
            { name: "text", value: WStr("a") },
            { name: "maxWidthPx", value: WNum(Math.NaN) },
        ]), Canonical.KIND_SNAPSHOT);
        CanonicalTestSupport.assertHex(recorder, "withNaN", CanonicalTestSupport.hexOf(withoutWidth), withNaN);
        final minusZero = Canonical.encode(WObj([
            { name: "text", value: WStr("a") },
            { name: "maxWidthPx", value: WNum(-0.0) },
        ]), Canonical.KIND_SNAPSHOT);
        final plusZero = Canonical.encode(WObj([
            { name: "text", value: WStr("a") },
            { name: "maxWidthPx", value: WNum(0.0) },
        ]), Canonical.KIND_SNAPSHOT);
        CanonicalTestSupport.assertHex(recorder, "minusZero", CanonicalTestSupport.hexOf(plusZero), minusZero);
    }

    @:test
    public static function digestMatchesThePlatformHash():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("CanonicalTest");
        recorder.section("digestMatchesThePlatformHash");
        final encoded = Canonical.encode(CanonicalTestSupport.WireObj("p-1", "中文", WNum(144)), Canonical.KIND_SNAPSHOT);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("0884bb15dee00d579efe3a63fc65344ed80b1f753fa04a2cdd2ccc830bd69c60",
            CanonicalTestSupport.hexOfDigest(encoded));
    }
}