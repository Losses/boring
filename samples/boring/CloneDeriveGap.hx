package boring;

// A plain (non-@:dataClass) class with all-Clone fields, mirroring
// org.tiqian.core.IntRange in the consumption tree. RustDecl.isCloneType
// returns false for a plain class, so a @:dataClass that holds one is
// denied #[derive(Clone)] even though its lowered struct is cloneable.
class CloneDeriveRange {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        this.start = start;
        this.end = end;
    }
}

// A @:dataClass whose instance fields are all Clone-capable once the plain
// class field is accounted for, mirroring LayoutResult/LineBox. Because
// isAllClone rejects the plain-class field, no #[derive(Clone)] is emitted
// while the read sites below append `.clone()`.
@:dataClass
class CloneDeriveResult {
    public final range:CloneDeriveRange;
    public final label:String;

    public function new(range:CloneDeriveRange, label:String) {
        this.range = range;
        this.label = label;
    }
}

class CloneDeriveGapOps {
    public static function resolve():String {
        final r = new CloneDeriveResult(new CloneDeriveRange(1, 3), "x");
        return r.range.toString() + ":" + r.label;
    }
}