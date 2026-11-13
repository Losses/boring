package boundaryscope;

/**
    The E0592 shape, first half: the no-argument overload. Haxe has no
    overloading, so the line overload lives in a second class
    (LayoutResultLineFns) — exactly the split tiqian's engine does. Two classes
    then claim one method name for one receiver type, and the base compiler
    emitted both as inherent methods on LayoutResult.
    (ExtensionNameCollision)
**/
class LayoutResultFns {
    @:extension
    public static function positionedClusters(result:LayoutResult):Int {
        return result.clusters.length;
    }
}
