package org.tiqian.protocol;

class TableProbe {
    public var text:String;
    public var advancePx:Float;
    public var fontSizePx:Float;
    public var fontWeight:Float;
    public var italic:Bool;
    public var script:String;
    public var language:String;
    public var features:Array<String>;

    public function new(text:String, advancePx:Float, fontSizePx:Float, fontWeight:Float, italic:Bool,
            script:String, language:String, features:Array<String>) {
        this.text = text;
        this.advancePx = advancePx;
        this.fontSizePx = fontSizePx;
        this.fontWeight = fontWeight;
        this.italic = italic;
        this.script = script;
        this.language = language;
        this.features = features;
    }
}

/**
 * The stored table form: every region decoded or lowered verbatim, so
 * encodeData over it reproduces the same bytes. The parallel arrays mirror
 * the file layout column by column (snapshot-table-binary.ts:22-49).
 */
