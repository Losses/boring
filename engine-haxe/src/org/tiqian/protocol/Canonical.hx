package org.tiqian.protocol;

import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.FPHelper;

/**
 * The canonical byte form of one submission (ADR 0052), single-sourced in
 * Haxe and generated for TypeScript and Rust. The bytes are the hash
 * preimage of the Paragraph and FontContracts cache layers and the content
 * encoding of the binary bridge. Golden vectors live in CanonicalTest and
 * pin the same hex strings the platform tests carry
 * (platforms/web/server/core/test/canonical.test.ts:16 ff., Rust unit tests
 * of canonical.rs).
 *
 * Byte order and semantics follow the existing implementations, which are
 * the authority: canonical.ts:18 magic "TQCS" ascii, canonical.ts:71
 * setFloat64 little-endian, canonical.ts:76/:86 setUint32 little-endian;
 * canonical.rs:89/:93 to_le_bytes. Every multi-byte integer is
 * little-endian and every f64 rides its IEEE 754 bit pattern little-endian:
 * the low u32 word goes out first, each u32 goes out low-byte first.
 *
 * Two semantic rules are carried explicitly (canonical.rs:54 canonical_f64,
 * canonical.ts:303): a non-finite number drops out of the form, and both
 * zero signs collapse to +0. Optional numeric fields are a present flag
 * followed by the f64 bytes (canonical.rs:382, canonical.ts:113). The
 * caller's logical `key` is deliberately absent. The digest itself stays
 * platform-side in P1 (node:crypto, the sha2 crate); this module exposes
 * the single-source entry through haxe.crypto.Sha256 for the follow-up
 * task that rewires the consumers.
 */
class Canonical {
    /** The canonical form's magic and version, shared with every encoder. */
    public static inline var MAGIC:String = "TQCS";
    public static inline var VERSION:Int = 1;
    /** Snapshot paragraph submission: carries `maxWidthPx`. */
    public static inline var KIND_SNAPSHOT:Int = 0;
    /** Font contract submission: the capture width is derived in Rust. */
    public static inline var KIND_CONTRACT:Int = 1;

    static inline var SEM_ATTRS:Int = 0x01;
    static inline var SEM_ORDER:Int = 0x02;
    static inline var SEM_TAG_NAME:Int = 0x04;

    static inline var SPAN_FAMILIES:Int = 0x01;
    static inline var SPAN_FONT_SIZE_PX:Int = 0x02;
    static inline var SPAN_FONT_WEIGHT:Int = 0x04;
    static inline var SPAN_ITALIC:Int = 0x08;
    static inline var SPAN_BASELINE_SHIFT_PX:Int = 0x10;

    static inline var BOX_INLINE_START_PX:Int = 0x01;
    static inline var BOX_INLINE_END_PX:Int = 0x02;
    static inline var BOX_OUTER_SPACING:Int = 0x04;

    /**
     * The content hash of the canonical bytes, the single-source digest
     * entry. P1 keeps the platform consumers (node:crypto, sha2 crate) on
     * their own implementations; the golden vectors assert this entry
     * agrees with them byte for byte.
     */
    public static function digest(data:Bytes):Bytes {
        return Sha256.make(data);
    }

    /**
     * Encodes one wire input into its canonical bytes. `kind` selects the
     * snapshot or contract form; snapshot inputs carry `maxWidthPx`,
     * contract inputs never do. A named issue comes back as Err; the
     * platform adapters raise it in their own error type.
     */
    public static function encode(input:WireValue, kind:Int):EncodeResult {
        final writer = new Writer();
        writer.begin(kind);
        final text = member(input, "text");
        var textValue = "";
        if (!isWireNull(text)) {
            textValue = JsCoerce.toString(text);
        }
        writer.str(textValue);
        if (kind == KIND_SNAPSHOT) {
            numberField(writer, numberMember(input, "maxWidthPx"));
        }
        final semantics = encodeSemantics(writer, member(input, "semantics"));
        if (semantics != "") {
            return CErr(semantics);
        }
        final spans = encodeTextSpans(writer, member(input, "textSpans"));
        if (spans != "") {
            return CErr(spans);
        }
        final boxes = encodeInlineBoxes(writer, member(input, "inlineBoxes"));
        if (boxes != "") {
            return CErr(boxes);
        }
        // A non-array reads as absent boundaries, the capture loop's own rule.
        final boundaries = arrOfNullable(member(input, "sourceBoundaries"));
        writer.u32(boundaries.length);
        var boundaryIndexIdx:Int = 0;
        while (boundaryIndexIdx < boundaries.length) {
            final boundary = boundaries[boundaryIndexIdx];
            final value = canonicalF64(JsCoerce.toNumber(boundary));
            // Non-finite boundaries keep the JSON lane's value: null, which
            // reads as zero through the loose number coercion.
            writer.f64(value == null ? 0.0 : value);
            boundaryIndexIdx++;
        }
        return COk(writer.finish());
    }

    /** The coalesced member: absent and null both read as WNull. */
    public static function member(input:WireValue, name:String):WireValue {
        if (isWireObj(input)) {
            return memberOfFields(objFields(input), name);
        }
        return WNull;
    }

    static function memberOfFields(fields:Array<WireField>, name:String):WireValue {
        var fieldIndexIdx:Int = 0;
        while (fieldIndexIdx < fields.length) {
            final field = fields[fieldIndexIdx];
            if (field.name == name) {
                return field.value;
            }
            fieldIndexIdx++;
        }
        return WNull;
    }

    /**
     * A number the way `JSON.stringify` carries it: non-finite values drop
     * out (they serialize as null, which readers coalesce away) and both
     * zero signs collapse to +0.
     */
    static function canonicalF64(value:Float):Null<Float> {
        if (!Math.isFinite(value)) {
            return null;
        }
        return value == 0.0 ? 0.0 : value;
    }

    /** `Number(member)` when the member survives, absent otherwise. */
    static function numberMember(input:WireValue, name:String):Null<Float> {
        final resolved = member(input, name);
        if (resolved == WNull) {
            return null;
        }
        return canonicalF64(JsCoerce.toNumber(resolved));
    }

    /** An optional numeric field: present flag plus the f64 bytes. */
    static function numberField(writer:Writer, value:Null<Float>):Void {
        if (value == null) {
            writer.u8(0);
        } else {
            writer.u8(1);
            writer.f64(value);
        }
    }

    /** One list value: absent reads as empty, a non-array is a named issue. */
    static function listMember(value:WireValue):ListShape {
        if (isWireNull(value)) {
            return LAbsent;
        }
        if (isWireArr(value)) {
            return LArr(arrOf(value));
        }
        return LBad;
    }

    static function isWireNull(value:WireValue):Bool {
        return switch (value) {
            case WNull: true;
            case WBool(_): false;
            case WNum(_): false;
            case WStr(_): false;
            case WArr(_): false;
            case WObj(_): false;
        };
    }

    static function isWireArr(value:WireValue):Bool {
        return switch (value) {
            case WArr(_): true;
            case WNull: false;
            case WBool(_): false;
            case WNum(_): false;
            case WStr(_): false;
            case WObj(_): false;
        };
    }

    static function isWireObj(value:WireValue):Bool {
        return switch (value) {
            case WObj(_): true;
            case WNull: false;
            case WBool(_): false;
            case WNum(_): false;
            case WStr(_): false;
            case WArr(_): false;
        };
    }

    static function arrOf(value:WireValue):Array<WireValue> {
        return switch (value) {
            case WArr(items): items;
            case WNull: new Array<WireValue>();
            case WBool(_): new Array<WireValue>();
            case WNum(_): new Array<WireValue>();
            case WStr(_): new Array<WireValue>();
            case WObj(_): new Array<WireValue>();
        };
    }

    static function arrOfNullable(value:WireValue):Array<WireValue> {
        return switch (value) {
            case WArr(items): items;
            case WNull: new Array<WireValue>();
            case WBool(_): new Array<WireValue>();
            case WNum(_): new Array<WireValue>();
            case WStr(_): new Array<WireValue>();
            case WObj(_): new Array<WireValue>();
        };
    }

    static function objFields(value:WireValue):Array<WireField> {
        return switch (value) {
            case WObj(fields): fields;
            case WNull: new Array<WireField>();
            case WBool(_): new Array<WireField>();
            case WNum(_): new Array<WireField>();
            case WStr(_): new Array<WireField>();
            case WArr(_): new Array<WireField>();
        };
    }

    static function isBadShape(shape:ListShape):Bool {
        return switch (shape) {
            case LBad: true;
            case LAbsent: false;
            case LArr(_): false;
        };
    }

    static function shapeItems(shape:ListShape):Array<WireValue> {
        return switch (shape) {
            case LAbsent: new Array<WireValue>();
            case LArr(items): items;
            case LBad: new Array<WireValue>();
        };
    }

    static function encodeSemantics(writer:Writer, value:WireValue):String {
        final shape = listMember(value);
        if (isBadShape(shape)) {
            return "InvalidSnapshotSemantics";
        }
        final items = shapeItems(shape);
        writer.u32(items.length);
        var spanIndexIdx:Int = 0;
        while (spanIndexIdx < items.length) {
            final span = items[spanIndexIdx];
            final attributes = member(span, "attributes");
            final order = numberMember(span, "order");
            final tagName = member(span, "tagName");
            var flags = 0;
            if (attributes != WNull) {
                flags |= SEM_ATTRS;
            }
            if (order != null) {
                flags |= SEM_ORDER;
            }
            if (tagName != WNull) {
                flags |= SEM_TAG_NAME;
            }
            writer.u8(flags);
            numberField(writer, numberMember(span, "start"));
            numberField(writer, numberMember(span, "end"));
            if (tagName != WNull) {
                writer.str(JsCoerce.toString(tagName));
            }
            if (order != null) {
                writer.f64(order);
            }
            if (attributes != WNull) {
                encodeAttributes(writer, attributes);
            }
            spanIndexIdx++;
        }
        return "";
    }

    static function encodeTextSpans(writer:Writer, value:WireValue):String {
        final shape = listMember(value);
        if (isBadShape(shape)) {
            return "InvalidSnapshotTextSpans";
        }
        final items = shapeItems(shape);
        writer.u32(items.length);
        var spanIndexIdx:Int = 0;
        while (spanIndexIdx < items.length) {
            final span = items[spanIndexIdx];
            final hasFamilies = familiesPresent(span);
            final families = familiesOf(span);
            final fontSizePx = numberMember(span, "fontSizePx");
            final fontWeight = numberMember(span, "fontWeight");
            final hasItalic = italicPresent(span);
            final italicValue = italicValueOf(span);
            final baselineShiftPx = numberMember(span, "baselineShiftPx");
            var flags = 0;
            if (hasFamilies) {
                flags |= SPAN_FAMILIES;
            }
            if (fontSizePx != null) {
                flags |= SPAN_FONT_SIZE_PX;
            }
            if (fontWeight != null) {
                flags |= SPAN_FONT_WEIGHT;
            }
            if (hasItalic) {
                flags |= SPAN_ITALIC;
            }
            if (baselineShiftPx != null) {
                flags |= SPAN_BASELINE_SHIFT_PX;
            }
            writer.u8(flags);
            numberField(writer, numberMember(span, "start"));
            numberField(writer, numberMember(span, "end"));
            if (hasFamilies) {
                writer.u32(families.length);
                var nameIndexIdx:Int = 0;
                while (nameIndexIdx < families.length) {
                    writer.str(families[nameIndexIdx]);
                    nameIndexIdx++;
                }
            }
            if (fontSizePx != null) {
                writer.f64(fontSizePx);
            }
            if (fontWeight != null) {
                writer.f64(fontWeight);
            }
            if (hasItalic) {
                writer.u8(italicValue ? 1 : 0);
            }
            if (baselineShiftPx != null) {
                writer.f64(baselineShiftPx);
            }
            spanIndexIdx++;
        }
        return "";
    }

    static function encodeInlineBoxes(writer:Writer, value:WireValue):String {
        final shape = listMember(value);
        if (isBadShape(shape)) {
            return "InvalidSnapshotInlineBoxes";
        }
        final items = shapeItems(shape);
        writer.u32(items.length);
        var itemIndexIdx:Int = 0;
        while (itemIndexIdx < items.length) {
            final item = items[itemIndexIdx];
            final inlineStartPx = numberMember(item, "inlineStartPx");
            final inlineEndPx = numberMember(item, "inlineEndPx");
            final outerSpacing = member(item, "outerSpacing");
            var flags = 0;
            if (inlineStartPx != null) {
                flags |= BOX_INLINE_START_PX;
            }
            if (inlineEndPx != null) {
                flags |= BOX_INLINE_END_PX;
            }
            if (outerSpacing != WNull) {
                flags |= BOX_OUTER_SPACING;
            }
            writer.u8(flags);
            numberField(writer, numberMember(item, "start"));
            numberField(writer, numberMember(item, "end"));
            if (inlineStartPx != null) {
                writer.f64(inlineStartPx);
            }
            if (inlineEndPx != null) {
                writer.f64(inlineEndPx);
            }
            if (outerSpacing != WNull) {
                writer.str(JsCoerce.toString(outerSpacing));
            }
            itemIndexIdx++;
        }
        return "";
    }

    static function familiesPresent(span:WireValue):Bool {
        return isWireArr(member(span, "fontFamilies"));
    }

    static function familiesOf(span:WireValue):Array<String> {
        return familiesFromList(arrOf(member(span, "fontFamilies")));
    }

    static function familiesFromList(list:Array<WireValue>):Array<String> {
        final names = new Array<String>();
        var itemIndexIdx:Int = 0;
        while (itemIndexIdx < list.length) {
            names.push(JsCoerce.toString(list[itemIndexIdx]));
            itemIndexIdx++;
        }
        return names;
    }

    static function italicPresent(span:WireValue):Bool {
        return isWireBool(member(span, "italic"));
    }

    static function italicValueOf(span:WireValue):Bool {
        return boolOf(member(span, "italic"));
    }

    static function isWireBool(value:WireValue):Bool {
        return switch (value) {
            case WBool(_): true;
            case WNull: false;
            case WNum(_): false;
            case WStr(_): false;
            case WArr(_): false;
            case WObj(_): false;
        };
    }

    static function boolOf(value:WireValue):Bool {
        return switch (value) {
            case WBool(inner): inner;
            case WNull: false;
            case WNum(_): false;
            case WStr(_): false;
            case WArr(_): false;
            case WObj(_): false;
        };
    }

    /**
     * Attributes keep their two wire shapes: an object becomes its string
     * pairs in insertion order, an array rides as its JSON text so invalid
     * pair shapes reproduce the reader's named error on the other side. Any
     * other shape reads as empty attributes.
     */
    static function encodeAttributes(writer:Writer, value:WireValue):Void {
        if (isWireObj(value)) {
            encodeObjectAttributes(writer, objFields(value));
            return;
        }
        if (isWireArr(value)) {
            writer.u8(2);
            writer.str(JsCoerce.renderJson(value));
            return;
        }
        writer.u8(0);
    }

    static function encodeObjectAttributes(writer:Writer, fields:Array<WireField>):Void {
        writer.u8(1);
        writer.u32(fields.length);
        var fieldIndexIdx:Int = 0;
        while (fieldIndexIdx < fields.length) {
            final field = fields[fieldIndexIdx];
            writer.str(field.name);
            writer.str(JsCoerce.toString(field.value));
            fieldIndexIdx++;
        }
    }
}

private enum ListShape {
    LAbsent;
    LArr(items:Array<WireValue>);
    LBad;
}

/**
 * Grows the canonical buffer in chunks; every multi-byte integer is
 * little-endian and every f64 rides its IEEE 754 bit pattern. The shape
 * mirrors samples/boring/BinaryWriter.hx; the byte order differs on
 * purpose, the canonical form is little-endian end to end (canonical.ts:71,
 * canonical.rs:93).
 */
private class Writer {
    final buf:BytesBuffer;

    public function new() {
        buf = new BytesBuffer();
    }

    /** Writes the header bytes; call exactly once, right after new. */
    public function begin(kind:Int):Void {
        writeMagic();
        u8(Canonical.VERSION);
        u8(kind);
    }

    function writeMagic():Void {
        buf.add(Bytes.ofString(Canonical.MAGIC));
    }

    public function u8(value:Int):Void {
        buf.addByte(value & 0xFF);
    }

    public function u32(value:Int):Void {
        emitBits(value);
    }

    public function f64(value:Float):Void {
        final bits = FPHelper.doubleToI64(value);
        // Low word first, each word low byte first: together the little-
        // endian f64 (144.0 reads back 0000000000006240 in vector0).
        emitBits(bits.low);
        emitBits(bits.high);
    }

    function emitBits(value:Int):Void {
        buf.addByte(value & 0xFF);
        buf.addByte((value >>> 8) & 0xFF);
        buf.addByte((value >>> 16) & 0xFF);
        buf.addByte((value >>> 24) & 0xFF);
    }

    public function str(value:String):Void {
        final encoded = Bytes.ofString(value);
        u32(encoded.length);
        buf.add(encoded);
    }

    public function finish():Bytes {
        return buf.getBytes();
    }
}