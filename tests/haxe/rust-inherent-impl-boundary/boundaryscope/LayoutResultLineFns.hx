package boundaryscope;

/** The E0592 shape, second half: same receiver, same method name, extra
    parameter. (ExtensionNameCollision) **/
class LayoutResultLineFns {
    @:extension
    public static function positionedClusters(result:LayoutResult, line:Int):Int {
        return result.clusters.length + line;
    }
}
