package boring;

class CtorOmitTarget {
    public final width:Float;
    public final height:Float;
    public final count:Int;

    public function new(width:Float, ?height:Null<Float>, ?count:Null<Int>) {
        this.width = width;
        this.height = height == null ? 100.0 : height;
        this.count = count == null ? 5 : count;
    }
}

class CtorOmitOps {
    public static function make():Float {
        final t = new CtorOmitTarget(10.0);
        return t.width + t.height;
    }
}
