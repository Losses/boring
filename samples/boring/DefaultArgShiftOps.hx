package boring;

class DefaultArgShiftProbe {
    public var tag:String;

    public function new(?tag:String) {
        this.tag = tag == null ? "probe" : tag;
    }

    public function label():String {
        return this.tag;
    }
}

/**
    The later coalescing default reads the earlier parameter. A call that
    passes an explicit null for the defaulted slot, or that omits it while a
    later argument keeps its position, must resolve the read against the
    argument this call actually passes.
 */
class DefaultArgShiftOps {
    public static function pick(a:String, ?b:String):String {
        var normalized = b == null ? a : b;
        return normalized;
    }

    public static function callExplicitNull():String {
        return pick("alpha", null);
    }

    public static function callLaterGiven():String {
        return pick("alpha", "beta");
    }

    public static function chainedFallback(?fallback:Float, ?value:Float):Float {
        var resolvedFallback = fallback == null ? 2.5 : fallback;
        var resolvedValue = value == null ? fallback : value;
        return resolvedFallback + resolvedValue;
    }

    public static function callChainedLaterNull():Float {
        return chainedFallback(4.5, null);
    }

    public static function callChainedBothOmitted():Float {
        return chainedFallback();
    }

    public static function callChainedLaterOmitted():Float {
        return chainedFallback(3.5);
    }

    public static function callChainedBothGiven():Float {
        return chainedFallback(1.5, 8.0);
    }

    public static function callInstanceNull():String {
        final probe = new DefaultArgShiftInstance();
        return probe.decorate("core", null);
    }

    /** A middle slot omitted with a later argument passed positionally. */
    public static function run(base:Int, ?probe:DefaultArgShiftProbe, ?count:Int):String {
        var normalized = probe == null ? new DefaultArgShiftProbe("fresh") : probe;
        var slots = count == null ? 7 : count;
        return normalized.label() + ":" + base + ":" + slots;
    }

    public static function callMiddleNull():String {
        return run(3, null, 9);
    }

    public static function callMiddleSkipped():String {
        return run(3, new DefaultArgShiftProbe("given"));
    }

    /** Constructor form of the same shape. */
    public static function ctorExplicitNull():Float {
        final cut = new DefaultArgShiftCut(2.0, null, 8);
        return cut.height + cut.count;
    }

    /** Slots the call passes explicitly stay explicit. */
    public static function ctorLaterGiven():Float {
        final cut = new DefaultArgShiftCut(2.0, 4.5, 8);
        return cut.height;
    }
}

class DefaultArgShiftInstance {
    public function new() {}

    public function decorate(text:String, ?suffix:String):String {
        var normalized = suffix == null ? text : suffix;
        return normalized;
    }
}

/** Constructor whose middle parameter carries the parameter-reading default. */
class DefaultArgShiftCut {
    public final width:Float;
    public final height:Float;
    public final count:Int;

    public function new(width:Float, ?height:Null<Float>, ?count:Null<Int>) {
        this.width = width;
        this.height = height == null ? width : height;
        this.count = count == null ? 5 : count;
    }

    public function describe():String {
        return width + ":" + height + ":" + count;
    }
}
