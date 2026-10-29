package org.tiqian.protocol;

class MetricEntry {
    public var familiesRef:Int;
    public var weight:Float;
    public var italic:Int;
    public var roleRef:Int;
    public var faceSelectionRef:Int;
    /** Semantic values kept so pooling can run after the sort. */
    public var valuePoolRef:Int;
    /** Semantic values carried through lowering (decode leaves these empty). */
    public var valuesEm:Array<Null<Float>>;
    public var stored:Bool;

    public function new(familiesRef:Int, weight:Float, italic:Int, roleRef:Int, faceSelectionRef:Int, valuePoolRef:Int) {
        this.familiesRef = familiesRef;
        this.weight = weight;
        this.italic = italic;
        this.roleRef = roleRef;
        this.faceSelectionRef = faceSelectionRef;
        this.valuePoolRef = valuePoolRef;
        this.valuesEm = [];
        this.stored = false;
    }
}

/** One deduplicated metric value quintuple; null marks the absent slot. */
