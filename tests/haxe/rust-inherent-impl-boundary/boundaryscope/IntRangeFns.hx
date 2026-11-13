package boundaryscope;

/**
    The E0116 shape: an `@:extension` whose receiver is a plain class, so the
    emitted receiver type is a handle the crate does not declare. The base
    compiler emitted `impl Rc<RefCell<IntRange>> { fn is_empty_cluster_range(&self) }`
    and rustc rejected the inherent impl.
    (ExtensionReceiverOwnership)
**/
class IntRangeFns {
    @:extension
    public static function isEmptyClusterRange(range:IntRange):Bool {
        return range.first > range.last;
    }
}
