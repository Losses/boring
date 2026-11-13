package boundaryscope;

/**
    Calls every extension, so the fixture also locks the call-site side: the
    declaration and the reference must agree on the emitted form, and a
    contested name must not import two same-named free functions (E0252).
**/
class BoundaryProbe {
    public static function main():Void {
        final range = new IntRange(0, 3);
        final empty = IntRangeFns.isEmptyClusterRange(range);
        final result = new LayoutResult([1, 2]);
        final total = LayoutResultFns.positionedClusters(result)
            + LayoutResultLineFns.positionedClusters(result, 1);
        if (empty && total == -1)
            range.get_first();
    }
}
