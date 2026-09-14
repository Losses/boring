package boring;

#if rust_output
/**
    A constructor whose optional parameters are assigned to like-named fields
    from inside branches. The branch-assigned field keeps a local slot so the
    tail struct literal can consume it; that slot must not reuse the
    parameter name, so the null checks still read the optional parameter. The
    named fallbackBindingName rule covers the collision.
*/
class BranchedOptionalFieldHolder {
    public final penalty:Int;
    public final rate:Float;

    public function new(?penalty:Int, ?rate:Float) {
        if (penalty == null)
            this.penalty = 2;
        else
            this.penalty = penalty;
        if (rate == null)
            this.rate = 0.5;
        else
            this.rate = rate;
    }
}

class BranchedOptionalFieldOps {
    public static function penalty():Int {
        return new BranchedOptionalFieldHolder().penalty;
    }

    public static function rate():Float {
        return new BranchedOptionalFieldHolder().rate;
    }

    public static function explicit():Int {
        return new BranchedOptionalFieldHolder(9, 1.5).penalty;
    }
}
#else
class BranchedOptionalFieldOps {}
#end
