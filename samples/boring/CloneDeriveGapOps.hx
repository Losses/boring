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

    public function toString():String {
        return start + ".." + end;
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
    // Indexing a Haxe Array reads its element with Haxe value semantics; the
    // generator clones a non-Copy element out of the Vec. Passing the array in
    // as a parameter stops the constant folder from turning the index into a
    // local move, so the read site appends `.clone()`, which requires
    // CloneDeriveResult to carry #[derive(Clone)].
    public static function resolve(results:Array<CloneDeriveResult>):String {
        final r = results[0];
        return r.range.toString() + ":" + r.label;
    }
}
