package casee;

/**
    Probe payload type: a reference type with a method, so a read of a
    nullable field of this type is used as a *call receiver*. That is the
    shape kotlinc rejects with "only safe (?.) or non-null asserted (!!.)
    calls are allowed on a nullable receiver" when the receiver chain does
    not smart-cast.
**/
class Vec {
    public final x:Float;

    public function new(x:Float) {
        this.x = x;
    }

    public function magnitude():Float {
        return x < 0 ? -x : x;
    }
}
