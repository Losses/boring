package org.tiqian.protocol;

/**
 * The normalized typography a font session resolves against, single-sourced
 * from the Rust `normalize::SnapshotTypography` (ADR 0050). All twelve
 * values are post-normalization: defaults applied and units resolved, so the
 * font-contract cache key and the context fingerprint read them directly
 * without re-coercing. This is the shared input shape for both the
 * font-contract cache key (FontContract) and the context fingerprint.
 */
typedef SnapshotTypography = {
    /** Ordered render families, already trimmed and non-empty. */
    var fontFamilies:Array<String>;
    var fontSizePx:Float;
    var lineHeightPx:Float;
    var locale:String;
    /** CSS font-weight (1..1000). The Rust field is `i32`, but Haxe `Int`
        maps to `u32`; the two agree for every positive CSS weight, which is
        the only range the lanes feed. */
    var fontWeight:Int;
    var italic:Bool;
    var firstLineIndentIc:Float;
    var lineLengthGridEnabled:Bool;
    var letterSpacingPx:Float;
    var fontFeatureSettings:String;
    var fontVariationSettings:String;
    var fontVariantNumeric:String;
}
