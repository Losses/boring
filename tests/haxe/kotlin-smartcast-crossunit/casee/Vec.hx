package casee;

class Vec {
    public final x:Float;
    public function new(x:Float) { this.x = x; }
    public function magnitude():Float { return x < 0 ? -x : x; }
}
