package org.tiqian.protocol;

import haxe.io.Bytes;

/**
 * One @font-face input as the session layer consumes it for selection
 * (protocol 5.3 face selection input). Distinct from FontFaceRecord, the
 * CSSOM boundary record: this spec carries the engine/session-layer face
 * properties (weight, style, face index, source order) plus the raw font
 * bytes that the boundary record deliberately excludes.
 *
 * Field meanings:
 * - family / publicUrl / unicodeRange carry the descriptor values the
 *   selection keys join; unicodeRange is the raw descriptor string (range
 *   parsing stays in the shared CSSOM parser).
 * - source is the raw face bytes passed through untouched -- woff2/sfnt
 *   decode and validation stay in the platform shell.
 * - faceIndex is the resolved face index, null when unset.
 * - weight is the declared selector (FontWeightSpec).
 * - style is the trimmed lowercase descriptor value.
 * - sourceOrder is the declaration order, pre-validated by the session
 *   layer's orderedFaceSpecs; the Rust field is u32.
 */
typedef FontFaceSpec = {
    final family:String;
    final publicUrl:String;
    final source:Bytes;
    final faceIndex:Null<Float>;
    final weight:FontWeightSpec;
    final style:String;
    final unicodeRange:Null<String>;
    final sourceOrder:Int;
}
