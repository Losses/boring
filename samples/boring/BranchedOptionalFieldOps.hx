package boring;

#if rust_output
/**
    A constructor whose optional parameters are assigned to like-named fields
    from inside branches. The branch-assigned field keeps a local slot so the
    tail struct literal can consume it; that slot must not reuse the
    parameter name, so the null checks still read the optional parameter. A
    field with no literal default declares its Rust type and the branch
    assignments initialize it. The named fallbackBindingName rule covers the
    collision and the typed declaration.
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

interface BranchedOptionalRule {
    public function tag():String;
}

class BranchedOptionalConcreteRule implements BranchedOptionalRule {
    public function new() {}

    public function tag():String {
        return "concrete";
    }
}

class BranchedOptionalRuleHolder {
    public final rule:BranchedOptionalRule;

    public function new(?rule:BranchedOptionalRule) {
        if (rule == null)
            this.rule = new BranchedOptionalConcreteRule();
        else
            this.rule = rule;
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

    public static function ruleTag():String {
        return new BranchedOptionalRuleHolder().rule.tag();
    }
}
#else
class BranchedOptionalFieldOps {}
#end
