package boundaryscope;

/**
    A plain Haxe class. The Rust lowering gives it the handle ABI
    (`Rc<RefCell<IntRange>>`), so it is NOT a type this crate may write an
    inherent impl for: `impl Rc<RefCell<IntRange>>` is E0116.
    (ExtensionReceiverOwnership)
**/
class IntRange {
    public final start:Int;
    public final end:Int;

    public function new(start:Int, end:Int) {
        this.start = start;
        this.end = end;
    }

    public var first(get, never):Int;
    public var last(get, never):Int;

    public function get_first():Int {
        return start;
    }

    public function get_last():Int {
        return end;
    }
}
