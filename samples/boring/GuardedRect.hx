package boring;

#if rust_output
class GuardedRect {
    public var left:Float;
    public var top:Float;

    public function new(left:Float, top:Float) {
        this.left = left;
        this.top = top;
    }
}
#else
class GuardedRect {}
#end
