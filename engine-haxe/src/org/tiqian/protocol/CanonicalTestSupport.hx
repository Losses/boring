package org.tiqian.protocol;

class CanonicalTestSupport {
    public static function bytesOf(result:EncodeResult):Null<haxe.io.Bytes> {
        return switch (result) {
            case EncodeResult.COk(bytes): bytes;
            case EncodeResult.CErr(_): null;
        };
    }

    public static function hexBytes(bytes:haxe.io.Bytes):String {
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

    public static function hexOf(result:EncodeResult):String {
        return switch (result) {
            case EncodeResult.COk(bytes): hexBytes(bytes);
            case EncodeResult.CErr(_): "<encode failed>";
        };
    }

    public static function hexOfDigest(result:EncodeResult):String {
        return switch (result) {
            case EncodeResult.COk(bytes): hexBytes(Canonical.digest(bytes));
            case EncodeResult.CErr(_): "<encode failed>";
        };
    }

    public static function WireObj(key:String, text:String, width:WireValue):WireValue {
        final fields:Array<WireField> = [{ name: "key", value: WStr(key) }, { name: "text", value: WStr(text) }];
        if (width != null) {
            fields.push({ name: "maxWidthPx", value: width });
        }
        return WObj(fields);
    }

    public static function FULL_VECTOR_INPUT():WireValue {
        return WObj([
            { name: "key", value: WStr("p-2") },
            { name: "text", value: WStr("中文字排版") },
            { name: "maxWidthPx", value: WNum(144) },
            { name: "semantics", value: WArr([
                WObj([
                    { name: "tagName", value: WStr("a") },
                    { name: "start", value: WNum(2) },
                    { name: "end", value: WNum(4) },
                    { name: "attributes", value: WObj([
                        { name: "href", value: WStr("https://example.com") },
                        { name: "class", value: WStr("link") },
                    ]) },
                    { name: "order", value: WNum(1) },
                ]),
                WObj([
                    { name: "tagName", value: WStr("em") },
                    { name: "start", value: WNum(0) },
                    { name: "end", value: WNum(1) },
                ]),
            ]) },
            { name: "textSpans", value: WArr([
                WObj([
                    { name: "start", value: WNum(0) },
                    { name: "end", value: WNum(2) },
                    { name: "fontFamilies", value: WArr([WStr("Dela Gothic One")]) },
                    { name: "fontSizePx", value: WNum(18) },
                    { name: "fontWeight", value: WNum(400) },
                    { name: "italic", value: WBool(true) },
                    { name: "baselineShiftPx", value: WNum(-0.5) },
                ]),
                WObj([
                    { name: "start", value: WNum(2) },
                    { name: "end", value: WNum(4) },
                    { name: "fontFamilies", value: WArr([]) },
                ]),
            ]) },
            { name: "inlineBoxes", value: WArr([
                WObj([
                    { name: "start", value: WNum(1) },
                    { name: "end", value: WNum(2) },
                    { name: "inlineStartPx", value: WNum(8) },
                    { name: "inlineEndPx", value: WNum(4) },
                    { name: "outerSpacing", value: WStr("Source") },
                ]),
                WObj([
                    { name: "start", value: WNum(3) },
                    { name: "end", value: WNum(4) },
                ]),
            ]) },
            { name: "sourceBoundaries", value: WArr([WNum(0), WNum(18), WNum(36)]) },
        ]);
    }

    public static function LOOSE_VECTOR_INPUT():WireValue {
        return WObj([
            { name: "key", value: WStr("p-3") },
            { name: "text", value: WStr(" coerce ") },
            { name: "maxWidthPx", value: WStr("144.5") },
            { name: "semantics", value: WArr([
                WObj([
                    { name: "tagName", value: WStr("i") },
                    { name: "start", value: WStr("1") },
                    { name: "end", value: WNum(2) },
                    { name: "attributes", value: WArr([
                        WArr([WStr("a"), WStr("1")]),
                        WArr([WStr("b"), WNum(2)]),
                    ]) },
                ]),
            ]) },
            { name: "textSpans", value: WArr([
                WObj([
                    { name: "start", value: WNum(0) },
                    { name: "end", value: WNum(1) },
                    { name: "italic", value: WStr("no") },
                ]),
            ]) },
            { name: "inlineBoxes", value: WArr([
                WObj([
                    { name: "start", value: WNum(0) },
                    { name: "end", value: WNum(1) },
                    { name: "outerSpacing", value: WNum(7) },
                ]),
            ]) },
            { name: "sourceBoundaries", value: WArr([WStr("3"), WNull]) },
        ]);
    }

    public static function assertHex(recorder:org.tiqian.test.trace.TestTraceRecorder, label:String, expected:String, result:EncodeResult):Void {
        recorder.record(label);
        org.tiqian.test.trace.TracedAssertions.assertEqualsString(expected, hexOf(result), label);
    }
}