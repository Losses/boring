package org.tiqian.protocol;

import haxe.io.Bytes;

class SnapshotTableTestSupport {
    public static function hexBytes(bytes:Bytes):String {
        final digits = "0123456789abcdef";
        final out = new StringBuf();
        var indexIdx:Int = 0;
        while (indexIdx < bytes.length) {
            final byte = bytes.get(indexIdx);
            out.addChar(digits.charCodeAt((byte >> 4) & 15));
            out.addChar(digits.charCodeAt(byte & 15));
            indexIdx++;
        }
        return out.toString();
    }

    public static function assertHexBytes(recorder:org.tiqian.test.trace.TestTraceRecorder, label:String, expected:String, bytes:Bytes):Void {
        recorder.record(label);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(expected, hexBytes(bytes), label);
    }

    public static function goldenInput():TableInput {
        final metrics = new Array<TableMetricRow>();
        metrics.push(new TableMetricRow("Arial", 400.0, false, "sans", "fs-1", fiveValues(1.5, null, 2.0)));
        metrics.push(new TableMetricRow("宋体", 400.0, true, "sans", "fs-1", fiveValues(1.5, null, 2.0)));
        final probes = new Array<TableProbe>();
        probes.push(new TableProbe("汉", 12.5, 16.0, 400.0, false, "Hans", "zh", oneFeature()));
        probes.push(new TableProbe("字", 12.5, 16.0, 400.0, false, "Hans", "zh", oneFeature()));
        final faces = new Array<String>();
        faces.push("{\"family\":\"F\"}");
        final typographies = new Array<String>();
        final valueStyles = new Array<String>();
        valueStyles.push("vs-0");
        final preloads = new Array<String>();
        return new TableInput(single("replay-a"), metrics, probes, faces, typographies, valueStyles,
            preloads, "{\"backendRevision\":\"r1\"}");
    }

    public static function single(text:String):Array<String> {
        final out = new Array<String>();
        out.push(text);
        return out;
    }

    public static function oneFeature():Array<String> {
        final out = new Array<String>();
        out.push("liga");
        return out;
    }

    public static function fiveValues(a:Float, b:Null<Float>, c:Float):Array<Null<Float>> {
        final out = new Array<Null<Float>>();
        out.push(a);
        out.push(b);
        out.push(c);
        out.push(null);
        out.push(null);
        return out;
    }

    /** Two metrics with distinct values so the pool must hold two rows. */
    public static function twoPoolInput():TableInput {
        final metrics = new Array<TableMetricRow>();
        metrics.push(new TableMetricRow("Arial", 400.0, false, "sans", "fs-1", fiveValues(1.5, null, 2.0)));
        metrics.push(new TableMetricRow("宋体", 500.0, true, "sans", "fs-1", fiveValues(3.5, 4.0, 5.0)));
        final probes = new Array<TableProbe>();
        final empty = new Array<String>();
        final texts = new Array<String>();
        texts.push("{}");
        return new TableInput(texts, metrics, probes, empty, empty, empty, empty, "{}");
    }
}