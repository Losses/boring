package boring;

/** Regression fixture for nested data-class comparator references. */
@:dataClass
class CompareGateBoolInner {
    public final enabled:Bool;

    public function new(enabled:Bool) {
        this.enabled = enabled;
    }
}

@:dataClass
class CompareGateBoolOuter {
    public final inner:CompareGateBoolInner;

    public function new(inner:CompareGateBoolInner) {
        this.inner = inner;
    }
}

@:dataClass
class CompareGateSafeInner {
    public final rank:Int;
    public final label:String;

    public function new(rank:Int, label:String) {
        this.rank = rank;
        this.label = label;
    }
}

@:dataClass
class CompareGateSafeOuter {
    public final inner:CompareGateSafeInner;

    public function new(inner:CompareGateSafeInner) {
        this.inner = inner;
    }
}

@:dataClass
class CompareGateBoolGrand {
    public final value:CompareGateBoolOuter;

    public function new(value:CompareGateBoolOuter) {
        this.value = value;
    }
}

@:dataClass
class CompareGateSafeGrand {
    public final value:CompareGateSafeOuter;

    public function new(value:CompareGateSafeOuter) {
        this.value = value;
    }
}

class CompareGateOps {
    public static function boolNested():CompareGateBoolOuter {
        return new CompareGateBoolOuter(new CompareGateBoolInner(true));
    }

    public static function safeNested():CompareGateSafeGrand {
        return new CompareGateSafeGrand(new CompareGateSafeOuter(new CompareGateSafeInner(1, "a")));
    }
}
