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

// A plain string abstract erases to String in the Rust lowering, so a class
// that holds one is Clone-capable exactly when String is. isCloneTypeDepth
// rejected every abstract outside its short allowlist, which denied the
// derive to a class like org.tiqian.shaping.ReplayableFontFaceDescriptor
// whose id field is an abstract over String.
abstract CloneDeriveLabel(String) from String to String {}

// A plain class whose only non-atomic field is a string abstract, mirroring
// ReplayableFontFaceDescriptor. Before the underlying-type descent,
// isAllClone rejected the abstract field and no #[derive(Clone)] was emitted
// while the read sites below append `.clone()`.
class CloneDeriveAbstractResult {
    public final label:CloneDeriveLabel;
    public final size:Int;

    public function new(label:CloneDeriveLabel, size:Int) {
        this.label = label;
        this.size = size;
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

    // The same read over a class whose field is a plain abstract. The
    // element clone needs the abstract to count as a Clone field so the
    // struct keeps #[derive(Clone)].
    public static function resolveAbstract(results:Array<CloneDeriveAbstractResult>):String {
        final r = results[0];
        final label:String = r.label;
        return label + ":" + r.size;
    }
}
