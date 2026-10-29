package org.tiqian.protocol;

/**
 * A loaded face exactly as the font session reports it for fingerprinting
 * (Stage2 protocol 5.3 face selection, single-sourced from the Rust lane's
 * session::FaceInfo at session.rs:124). Distinct from FontFaceSpec, the raw
 * selector the host hands the session: this is the face AFTER selection,
 * carrying the resolved fallback order and the two byte digests the context
 * fingerprint reads.
 *
 * Field-for-field parity with the Rust struct:
 *   - weight: the resolved axis range, exactly two entries [min, max]
 *     (Rust [f64;2]); faceIndex: the resolved face index (f64);
 *     sourceOrder: the resolved fallback order (Rust u32, non-negative);
 *   - sourceSha256 / sfntSha256: lowercase hex digests the shell computed
 *     over the raw and decoded font bytes respectively;
 *   - axisTags / localNames: the sfnt axis tags and localized family names,
 *     both ordered as the shell reports them.
 */
typedef FaceInfo = {
    final family:String;
    final style:String;
    final weight:Array<Float>;
    final unicodeRange:String;
    final publicUrl:String;
    final sourceSha256:String;
    final sfntSha256:String;
    final faceIndex:Float;
    final sourceOrder:Int;
    final axisTags:Array<String>;
    final localNames:Array<String>;
}
