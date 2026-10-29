package org.tiqian.protocol;

class StyleRow {
    public var fontSizePx:Float;
    public var fontWeight:Float;
    public var italic:Int;
    public var scriptRef:Int;
    public var languageRef:Int;

    public function new(fontSizePx:Float, fontWeight:Float, italic:Int, scriptRef:Int, languageRef:Int) {
        this.fontSizePx = fontSizePx;
        this.fontWeight = fontWeight;
        this.italic = italic;
        this.scriptRef = scriptRef;
        this.languageRef = languageRef;
    }
}

/**
 * The semantic table input. The JSON text regions arrive pre-serialized:
 * faces, typographies, value styles and font preloads are canonical JSON
 * texts, the revision tail is one canonical JSON text (Stage1-P2 boundary
 * ruling; JSON production stays in the platform shells).
 */
