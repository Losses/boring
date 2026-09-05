package boring;

/** A record stored in array element positions (features/49: ReadOnlyArray). */
@:dataClass
class GlyphCluster {
    public var clusterRange:Int;
    public var start:Int;
    public var end:Int;

    public function new(clusterRange:Int, start:Int, end:Int) {
        this.clusterRange = clusterRange;
        this.start = start;
        this.end = end;
    }

    public var width(get, never):Int;

    public function get_width():Int
        return end - start;
}
