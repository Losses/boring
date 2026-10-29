package org.tiqian.protocol;

/**
 * One resolved style of a dash run, in the exact `JSON.stringify` field
 * order the js lane emits (ADR 0050). The order is the cache-key identity
 * order: two runs that differ only by member order still split the cache.
 */
private typedef DashStyle = {
    var fontFamilies:Array<String>;
    var fontSizePx:Float;
    var fontWeight:Float;
    var italic:WireValue;
    var baselineShiftPx:Float;
}

/**
 * The font-contract cache key (ADR 0050 parity oracle), single-sourced from
 * the Rust `font_contract::required_cjk_dash_contract_input`. When a
 * font-contract paragraph cannot be prepared, the `——` and `⸺` runs it
 * contained still need server shaping evidence, so every style that owns one
 * of those sequences contributes one minimal probe (key + probe text + one raw
 * span per probe). Groups keep first-seen style order and each group dedupes
 * its dash forms, byte-identical to the js `matchAll(/——|⸺/gu)` walk.
 */
class FontContract {
    public static function requiredCjkDashContractInput(key:WireValue, text:WireValue, textSpans:WireValue, typography:SnapshotTypography):Null<WireValue> {
        final textString = isWireNull(text) ? "" : JsCoerce.toString(text);
        final spans = arrOf(textSpans);

        final order:Array<Int> = [];
        final signatures:Array<String> = [];
        final styles:Array<DashStyle> = [];
        final dashesPerGroup:Array<Array<String>> = [];

        var offset:Float = 0.0;
        var i = 0;
        final len = textString.length;
        while (i < len) {
            final code = textString.charCodeAt(i);
            var dash = "";
            if (code == 0x2014 && i + 1 < len && textString.charCodeAt(i + 1) == 0x2014) {
                dash = "——";
            } else if (code == 0x2E3A) {
                dash = "⸺";
            }

            if (dash != "") {
                final style = resolvedStyleAt(offset, spans, typography);
                final signature = JsCoerce.renderJson(dashStyleToJson(style));
                var index = 0;
                var found = false;
                var searchIdx = 0;
                while (searchIdx < signatures.length) {
                    if (signatures[searchIdx] == signature) {
                        index = searchIdx;
                        found = true;
                        break;
                    }
                    searchIdx++;
                }
                if (!found) {
                    index = styles.length;
                    styles.push(style);
                    dashesPerGroup.push([]);
                    order.push(index);
                    signatures.push(signature);
                }
                var seen = false;
                var dashIdx = 0;
                while (dashIdx < dashesPerGroup[index].length) {
                    if (dashesPerGroup[index][dashIdx] == dash) {
                        seen = true;
                        break;
                    }
                    dashIdx++;
                }
                if (!seen) {
                    dashesPerGroup[index].push(dash);
                }
                if (dash == "——") {
                    offset += 2.0;
                    i += 2;
                } else {
                    offset += 1.0;
                    i += 1;
                }
            } else {
                if (code >= 0xD800 && code <= 0xDBFF) {
                    offset += 2.0;
                    i += 2;
                } else {
                    offset += 1.0;
                    i += 1;
                }
            }
        }

        if (styles.length == 0) return null;

        var probe = "";
        var probeLen:Float = 0.0;
        final outSpans:Array<WireValue> = [];
        for (index in order) {
            for (dash in dashesPerGroup[index]) {
                final start:Float = probeLen;
                probe += dash;
                probeLen += (dash == "——" ? 2.0 : 1.0);
                final end:Float = probeLen;
                final styleFields = objFields(dashStyleToJson(styles[index]));
                final fields:Array<WireField> = [
                    { name: "start", value: WNum(start) },
                    { name: "end", value: WNum(end) },
                ];
                for (sf in styleFields) fields.push(sf);
                outSpans.push(WObj(fields));
            }
        }

        return WObj([
            { name: "key", value: WStr(isWireNull(key) ? "" : JsCoerce.toString(key)) },
            { name: "text", value: WStr(probe) },
            { name: "textSpans", value: WArr(outSpans) },
        ]);
    }

    static function matchedSpanAt(textOffset:Float, spans:Array<WireValue>):WireValue {
        final n = spans.length;
        var k = 0;
        while (k < n) {
            final candidate = spans[n - 1 - k];
            final startRaw = Canonical.member(candidate, "start");
            final endRaw = Canonical.member(candidate, "end");
            if (isRawNumber(startRaw) && isRawNumber(endRaw)) {
                final start = rawNumber(startRaw);
                final end = rawNumber(endRaw);
                if (isSafeInteger(start) && isSafeInteger(end) && textOffset >= start && textOffset < end) {
                    return candidate;
                }
            }
            k++;
        }
        return WNull;
    }

    static function resolvedStyleAt(textOffset:Float, spans:Array<WireValue>, typography:SnapshotTypography):DashStyle {
        final matched = matchedSpanAt(textOffset, spans);

        var fontFamilies:Array<String> = typography.fontFamilies;
        final familiesRaw = Canonical.member(matched, "fontFamilies");
        if (isWireArr(familiesRaw)) {
            fontFamilies = mapStrings(arrOf(familiesRaw));
        }
        final fontSizePx:Float = coerceNumberOr(Canonical.member(matched, "fontSizePx"), typography.fontSizePx);
        final fontWeight:Float = coerceNumberOr(Canonical.member(matched, "fontWeight"), typography.fontWeight * 1.0);
        final italic:WireValue = italicOr(Canonical.member(matched, "italic"), typography.italic);
        final baselineShiftPx:Float = coerceNumberOr(Canonical.member(matched, "baselineShiftPx"), 0.0);

        return {
            fontFamilies: fontFamilies,
            fontSizePx: fontSizePx,
            fontWeight: fontWeight,
            italic: italic,
            baselineShiftPx: baselineShiftPx,
        };
    }

    static function dashStyleToJson(style:DashStyle):WireValue {
        final families:Array<WireValue> = [];
        for (family in style.fontFamilies) families.push(WStr(family));
        return WObj([
            { name: "fontFamilies", value: WArr(families) },
            { name: "fontSizePx", value: WNum(style.fontSizePx) },
            { name: "fontWeight", value: WNum(style.fontWeight) },
            { name: "italic", value: style.italic },
            { name: "baselineShiftPx", value: WNum(style.baselineShiftPx) },
        ]);
    }

    static function mapStrings(items:Array<WireValue>):Array<String> {
        final out:Array<String> = [];
        for (item in items) out.push(JsCoerce.toString(item));
        return out;
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

    static function isRawNumber(value:WireValue):Bool {
        return switch (value) {
            case WNum(_): true;
            case WNull: false;
            case WBool(_): false;
            case WStr(_): false;
            case WArr(_): false;
            case WObj(_): false;
        };
    }

    static function rawNumber(value:WireValue):Float {
        return switch (value) {
            case WNum(inner): inner;
            case WNull: 0.0;
            case WBool(_): 0.0;
            case WStr(_): 0.0;
            case WArr(_): 0.0;
            case WObj(_): 0.0;
        };
    }

    static function coerceNumberOr(value:WireValue, fallback:Float):Float {
        return switch (value) {
            case WNull: fallback;
            case WBool(inner): inner ? 1.0 : 0.0;
            case WNum(inner): inner;
            case WStr(inner): JsCoerce.toNumberFromString(inner);
            case WArr(_) | WObj(_): JsCoerce.toNumber(value);
        };
    }

    static function italicOr(value:WireValue, fallback:Bool):WireValue {
        return switch (value) {
            case WNull: WBool(fallback);
            case WBool(inner): WBool(inner);
            case WNum(inner): WNum(inner);
            case WStr(inner): WStr(inner);
            case WArr(inner): WArr(inner);
            case WObj(inner): WObj(inner);
        };
    }

    static function isSafeInteger(value:Float):Bool {
        return value % 1.0 == 0.0 && Math.abs(value) <= 9007199254740991.0;
    }
}
