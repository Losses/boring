package org.tiqian.protocol;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.FPHelper;

/**
 * The context fingerprint of one precomputer (ADR 0052), single-sourced from
 * the Rust lane's context.rs. It is the engine half of every font-session
 * cache key: the shell computes it once over the revisions that shape
 * artifact bytes, the shaping-engine version, the normalized typography and
 * the resolved face set in fallback order. Two precomputers produce
 * byte-compatible cache entries exactly when their fingerprints agree, so
 * this encoding is byte-exact, not merely semantically stable.
 *
 * harfbuzzVersion is deliberately a parameter: it names the shaping engine
 * the shell linked (the Rust lane's HARFBUZZ_VERSION, the wasm HarfBuzz
 * build on TS). That is engine identity rather than a single-source
 * revision, so it is not a Revision constant (see Revision.hx). HarfBuzz
 * and sfnt parsing stay platform-side; this layer only mixes the version
 * string into the key.
 *
 * Byte layout mirrors context.rs verbatim. Every section is one tag byte
 * then its little-endian payload: str is u32 LE length + UTF-8; i64 is 8
 * LE bytes (a positive CSS weight sign-extends to a positive i64, so the
 * low u32 rides out first and the high u32 is zero); f64 normalizes
 * non-finite and either zero sign to +0 then rides its IEEE bits LE; bool
 * is a single 0/1 byte; bytesStrList is a u32 LE count + per-item u32 LE
 * length + bytes (the caller emits the tag first). finish() is SHA-256
 * (Canonical.digest). The function returns 32 bytes.
 */
class ContextFingerprint {
    public static function contextFingerprint(
        typography:SnapshotTypography,
        faces:Array<FaceInfo>,
        harfbuzzVersion:String
    ):Bytes {
        final writer = new FingerprintWriter();
        writer.u32(0x01, Revision.SNAPSHOT_SCHEMA);
        writer.str(0x02, Revision.LAYOUT_REVISION);
        writer.str(0x03, Revision.RENDER_REVISION);
        writer.str(0x04, Revision.FONT_BACKEND_REVISION);
        writer.str(0x05, Revision.FONT_REPLAY_REVISION);
        writer.str(0x06, Revision.FONT_REPLAY_TRANSPORT);
        writer.str(0x07, Revision.FONT_SOURCE_POLICY);
        writer.str(0x08, harfbuzzVersion);
        writer.u32(0x09, Canonical.VERSION);
        writer.tag(0x10);
        writer.bytesStrList(typography.fontFamilies);
        writer.f64(0x11, typography.fontSizePx);
        writer.f64(0x12, typography.lineHeightPx);
        writer.str(0x13, typography.locale);
        writer.i64(0x14, typography.fontWeight);
        writer.bool(0x15, typography.italic);
        writer.f64(0x16, typography.firstLineIndentIc);
        writer.bool(0x17, typography.lineLengthGridEnabled);
        writer.f64(0x18, typography.letterSpacingPx);
        writer.str(0x19, typography.fontFeatureSettings);
        writer.str(0x1a, typography.fontVariationSettings);
        writer.str(0x1b, typography.fontVariantNumeric);
        writer.u32(0x1c, faces.length);
        for (face in faces) {
            encodeFace(writer, face);
        }
        return writer.finish();
    }

    static function encodeFace(writer:FingerprintWriter, face:FaceInfo):Void {
        writer.str(0x20, face.family);
        writer.str(0x21, face.style);
        writer.f64(0x22, face.weight[0]);
        writer.f64(0x23, face.weight[1]);
        writer.str(0x24, face.unicodeRange);
        writer.str(0x25, face.publicUrl);
        writer.str(0x26, face.sourceSha256);
        writer.str(0x27, face.sfntSha256);
        writer.f64(0x28, face.faceIndex);
        writer.u32(0x29, face.sourceOrder);
        writer.tag(0x2a);
        writer.bytesStrList(face.axisTags);
        writer.tag(0x2b);
        writer.bytesStrList(face.localNames);
    }
}

/**
 * Grows the fingerprint buffer; every multi-byte integer is little-endian
 * and every f64 rides its IEEE 754 bit pattern (low word first), the same
 * byte order as Canonical.Writer. Mirrors context.rs FingerprintWriter.
 */
private class FingerprintWriter {
    final buf:BytesBuffer;

    public function new() {
        buf = new BytesBuffer();
    }

    public function tag(tag:Int):Void {
        buf.addByte(tag & 0xFF);
    }

    public function str(tag:Int, value:String):Void {
        this.tag(tag);
        final encoded = Bytes.ofString(value);
        emitBits(encoded.length);
        buf.add(encoded);
    }

    public function u32(tag:Int, value:Int):Void {
        this.tag(tag);
        emitBits(value);
    }

    public function i64(tag:Int, value:Int):Void {
        this.tag(tag);
        // A positive CSS weight (the only range the lanes feed) sign-extends
        // to a positive i64 whose high word is zero: low u32 LE then zeros.
        emitBits(value);
        emitBits(0);
    }

    public function f64(tag:Int, value:Float):Void {
        this.tag(tag);
        final normalized = (!Math.isFinite(value) || value == 0.0) ? 0.0 : value;
        final bits = FPHelper.doubleToI64(normalized);
        emitBits(bits.low);
        emitBits(bits.high);
    }

    public function bool(tag:Int, value:Bool):Void {
        this.tag(tag);
        buf.addByte(value ? 1 : 0);
    }

    public function bytesStrList(values:Array<String>):Void {
        emitBits(values.length);
        for (value in values) {
            final encoded = Bytes.ofString(value);
            emitBits(encoded.length);
            buf.add(encoded);
        }
    }

    public function finish():Bytes {
        return Canonical.digest(buf.getBytes());
    }

    function emitBits(value:Int):Void {
        buf.addByte(value & 0xFF);
        buf.addByte((value >>> 8) & 0xFF);
        buf.addByte((value >>> 16) & 0xFF);
        buf.addByte((value >>> 24) & 0xFF);
    }
}
