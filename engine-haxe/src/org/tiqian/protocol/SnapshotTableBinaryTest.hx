package org.tiqian.protocol;

import haxe.io.Bytes;

/**
 * The snapshot-table binary inverse properties, closed in Haxe (research doc
 * 6.2): write then read restores the content, read then write reproduces the
 * exact bytes, and one golden vector pins the same byte group the exit
 * languages replay. Assertions go through haxe.io.Bytes.toHex
 * (stdlib/01-haxe-io-bytes.md line 21).
 */
class SnapshotTableBinaryTest {
    @:test
    public static function goldenVectorPinsTheSharedBytes():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("SnapshotTableBinaryTest");
        recorder.section("goldenVectorPinsTheSharedBytes");
        SnapshotTableTestSupport.assertHexBytes(recorder, "table-golden",
            "54495154424c3033010000000a00000002000000010000000200000001000000010000000100000001000000000000000100000000000000080000000500000004000000040000000600000003000000040000000200000004000000030000007265706c61792d61417269616c73616e7366732d31e5ae8be4bd93e6b18948616e737a686c696761e5ad970100000004000000000000000000794000000000000079400001020000000200000003000000030000000000000000000000000000000000f83f000000000000f87f0000000000000040000000000000f87f000000000000f87f0500000009000000000000000000000000000000000000000000294000000000000030400000000000007940000600000007000000060000000100080000000e0000007b2266616d696c79223a2246227d0400000076732d307b226261636b656e645265766973696f6e223a227231227d",
            SnapshotTableBinary.encode(SnapshotTableTestSupport.goldenInput()));
    }

    @:test
    public static function readThenWriteReproducesTheBytes():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("SnapshotTableBinaryTest");
        recorder.section("readThenWriteReproducesTheBytes");
        final encoded = SnapshotTableBinary.encode(SnapshotTableTestSupport.goldenInput());
        final data = new TableData();
        final issue = SnapshotTableBinary.decodeInto(encoded, data);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("", issue);
        SnapshotTableTestSupport.assertHexBytes(recorder, "reencode", SnapshotTableTestSupport.hexBytes(encoded),
            SnapshotTableBinary.encodeData(data));
    }

    @:test
    public static function writeThenReadRestoresTheContent():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("SnapshotTableBinaryTest");
        recorder.section("writeThenReadRestoresTheContent");
        final data = new TableData();
        final issue = SnapshotTableBinary.decodeInto(SnapshotTableBinary.encode(SnapshotTableTestSupport.goldenInput()), data);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("", issue);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.replayStringCount);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(10, data.strings.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsString("replay-a", data.strings[0]);
                org.tiqian.test.trace.TracedAssertions.assertEqualsString("宋体", data.strings[4]);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(2, data.metricRows.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.metricRows[0].familiesRef);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.metricRows[1].italic);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.valuePool.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(2, data.probeTextRefs.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.advancePool.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.styleFontSize.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.featuresPool.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.featuresPool[0].length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsString("{\"family\":\"F\"}", data.faceTexts[0]);
                org.tiqian.test.trace.TracedAssertions.assertEqualsString("vs-0", data.valueStyleTexts[0]);
                org.tiqian.test.trace.TracedAssertions.assertEqualsString("{\"backendRevision\":\"r1\"}", data.revisionText);
    }

    @:test
    public static function poolDeduplicationCollapsesEqualRows():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("SnapshotTableBinaryTest");
        recorder.section("poolDeduplicationCollapsesEqualRows");
        final data = new TableData();
        final issue = SnapshotTableBinary.decodeInto(SnapshotTableBinary.encode(SnapshotTableTestSupport.goldenInput()), data);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("", issue);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.valuePool.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.advancePool.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.styleFontSize.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.featuresPool.length);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(0, data.probeStyleRefs[0]);
                org.tiqian.test.trace.TracedAssertions.assertEqualsInt(0, data.probeStyleRefs[1]);
    }

    @:test
    public static function damagedFilesComeBackAsTheNamedIssue():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("SnapshotTableBinaryTest");
        recorder.section("damagedFilesComeBackAsTheNamedIssue");
        final short = new TableData();
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("SnapshotTablesInvalid",
            SnapshotTableBinary.decodeInto(Bytes.ofString("TIQ"), short));
        final corrupted = SnapshotTableBinary.encode(SnapshotTableTestSupport.goldenInput());
        corrupted.set(3, 0x58);
        final badMagic = new TableData();
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("SnapshotTablesInvalid",
            SnapshotTableBinary.decodeInto(corrupted, badMagic));
    }


    /**
     * Regression for the dropped value-pool ref write: a table whose two
     * metric rows fall into two distinct pool rows must decode with refs 0
     * and 1, and re-encoding must reproduce the bytes exactly. Both checks
     * fail if the pool ref assignment is silently lost (the ref collapses
     * to 0 and the pool collapses to one row).
     */
    @:test
    public static function poolRefsSurviveDecodeReencode():Void {
        final recorder = new org.tiqian.test.trace.TestTraceRecorder("SnapshotTableBinaryTest");
        recorder.section("poolRefsSurviveDecodeReencode");
        final input = SnapshotTableTestSupport.twoPoolInput();
        final bytes = SnapshotTableBinary.encode(input);
        final data = new TableData();
        final issue = SnapshotTableBinary.decodeInto(bytes, data);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString("", issue);
        org.tiqian.test.trace.TracedAssertions.assertEqualsInt(2, data.valuePool.length);
        org.tiqian.test.trace.TracedAssertions.assertEqualsInt(0, data.metricRows[0].valuePoolRef);
        org.tiqian.test.trace.TracedAssertions.assertEqualsInt(1, data.metricRows[1].valuePoolRef);
        SnapshotTableTestSupport.assertHexBytes(recorder, "refreeze",
            SnapshotTableTestSupport.hexBytes(bytes),
            SnapshotTableBinary.encodeData(data));
    }

}