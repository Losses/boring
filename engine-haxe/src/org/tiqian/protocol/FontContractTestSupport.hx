package org.tiqian.protocol;

/**
 * Shared builders for FontContractTest golden vectors. Kept as an ordinary
 * class (not a test class) so the test runner does not reject its helper
 * members as "non-test members".
 */
class FontContractTestSupport {
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

    public static function run(key:WireValue, text:WireValue, spans:WireValue):Null<String> {
        final probe = FontContract.requiredCjkDashContractInput(key, text, spans, typography());
        return probe == null ? null : JsCoerce.renderJson(probe);
    }
}
