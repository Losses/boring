package org.tiqian.protocol;

/**
 * Declared descriptors of one CSSOM `@font-face` rule that identify the
 * face for selection. This is the protocol boundary record produced by
 * `@font-face` parsing and consumed by face selection.
 *
 * Field meanings:
 * - `family` carries the `font-family` descriptor value.
 * - `localNames` carries the source names declared through `local()`
 *   in the `src` descriptor, in declaration order.
 * - `unicodeRange` carries the raw `unicode-range` descriptor string.
 *   Range parsing stays in the shared CSSOM parser.
 * - `publicUrl` carries the `url()` source declared in the `src`
 *   descriptor.
 *
 * Face properties that belong to the engine or the font session layer
 * (style, weight, face index, source order) stay out of this record.
 */
typedef FontFaceRecord = {
    final family:String;
    final localNames:Array<String>;
    final unicodeRange:String;
    final publicUrl:String;
}
