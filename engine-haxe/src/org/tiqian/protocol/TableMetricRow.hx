package org.tiqian.protocol;

class TableMetricRow {
    public var serializedFamilies:String;
    public var fontWeight:Float;
    public var italic:Bool;
    public var role:String;
    public var faceSelectionText:String;
    public var valuesEm:Array<Null<Float>>;

    public function new(serializedFamilies:String, fontWeight:Float, italic:Bool, role:String,
            faceSelectionText:String, valuesEm:Array<Null<Float>>) {
        this.serializedFamilies = serializedFamilies;
        this.fontWeight = fontWeight;
        this.italic = italic;
        this.role = role;
        this.faceSelectionText = faceSelectionText;
        this.valuesEm = valuesEm;
    }
}

/** One semantic probe row. */
