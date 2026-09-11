package boring;

#if swift_output
class NullGuardFieldMetrics {
    public var typoAscent:Null<Float>;
    public var ascent:Float;
    public var reason:Null<String>;

    public function new(typoAscent:Null<Float>, ascent:Float, reason:Null<String>) {
        this.typoAscent = typoAscent;
        this.ascent = ascent;
        this.reason = reason;
    }
}
#else
class NullGuardFieldMetrics {}
#end
