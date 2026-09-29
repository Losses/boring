package comparisoncollision;

@:dataClass
class PairKey {
    public final first:comparisoncollision.first.Point;
    public final second:comparisoncollision.second.Point;

    public function new(first:comparisoncollision.first.Point, second:comparisoncollision.second.Point) {
        this.first = first;
        this.second = second;
    }
}
