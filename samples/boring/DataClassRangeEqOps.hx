package boring;

@:dataClass
class RangeMark {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        this.start = start;
        this.end = end;
    }
}

@:dataClass
class SpanQuery {
    public final range:RangeMark;
    public final label:String;

    public function new(range:RangeMark, label:String) {
        this.range = range;
        this.label = label;
    }
}

class DataClassRangeEqOps {
    public static function rangesEqual():Bool {
        final a = new SpanQuery(new RangeMark(1, 5), "alpha");
        final b = new SpanQuery(new RangeMark(1, 5), "alpha");
        final c = new SpanQuery(new RangeMark(1, 6), "alpha");
        // Haxe classes use reference equality for `==`; compare fields for a portable value check.
        final equal = a.range.start == b.range.start && a.range.end == b.range.end && a.label == b.label;
        final different = a.range.start != c.range.start || a.range.end != c.range.end || a.label != c.label;
        return equal && different;
    }
}
