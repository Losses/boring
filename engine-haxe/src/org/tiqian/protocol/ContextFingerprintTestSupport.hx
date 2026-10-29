package org.tiqian.protocol;

/**
 * Shared builders for ContextFingerprintTest golden vectors. Kept as an
 * ordinary class (not a test class) so the test runner does not reject its
 * helper members as "non-test members".
 */
class ContextFingerprintTestSupport {
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

    public static function harfbuzzVersion():String {
        return "harfrust-0.13.0";
    }

    public static function typography():SnapshotTypography {
        return {
            fontFamilies: ["Dela Gothic One"],
            fontSizePx: 18.0,
            lineHeightPx: 27.0,
            locale: "",
            fontWeight: 400,
            italic: false,
            firstLineIndentIc: 0.0,
            lineLengthGridEnabled: false,
            letterSpacingPx: 0.0,
            fontFeatureSettings: "",
            fontVariationSettings: "",
            fontVariantNumeric: "",
        };
    }

    public static function typographyAt(fontSizePx:Float):SnapshotTypography {
        return {
            fontFamilies: ["Dela Gothic One"],
            fontSizePx: fontSizePx,
            lineHeightPx: 27.0,
            locale: "",
            fontWeight: 400,
            italic: false,
            firstLineIndentIc: 0.0,
            lineLengthGridEnabled: false,
            letterSpacingPx: 0.0,
            fontFeatureSettings: "",
            fontVariationSettings: "",
            fontVariantNumeric: "",
        };
    }

    public static function face():FaceInfo {
        return {
            family: "Test Face",
            style: "normal",
            weight: [400.0, 700.0],
            unicodeRange: "U+4E00-9FFF",
            publicUrl: "https://example.com/font.woff2",
            sourceSha256: "abcd0123",
            sfntSha256: "ef01",
            faceIndex: 1.0,
            sourceOrder: 3,
            axisTags: ["wght", "wdth"],
            localNames: ["Test Face"],
        };
    }
}
