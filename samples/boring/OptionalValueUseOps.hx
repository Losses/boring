package boring;

#if swift_output
enum OptionalValueUseTag {
    Wrap(value:Int);
}

/**
    A nullable value that reaches a value context Swift types as
    non-optional: an enum payload, an `if` test, a map lookup guard, a
    narrowed member operand, a negated operand, an augmented assignment,
    the string-concatenation leaf, and a ternary with a null arm in a
    non-optional return.
*/
class OptionalValueUseOps {
    public static function tag(raw:Null<Int>):OptionalValueUseTag {
        final value = raw == null ? 0 : raw;
        return OptionalValueUseTag.Wrap(value);
    }

    public static function tagValue(raw:Null<Int>):Int {
        return switch (tag(raw)) {
            case Wrap(value): value;
        };
    }

    public static function enabled(raw:Null<Bool>):Bool {
        final flag = raw == null ? true : raw;
        if (flag)
            return true;
        return false;
    }

    public static function lookup(values:std.SortedMap<Int, Float>, key:Int):Float {
        return values.get(key) == null ? 0.0 : values.get(key);
    }

    public static function metrics(metrics:OptionalValueUseMetrics, limit:Float):Bool {
        return metrics.advance != null && metrics.advance > limit;
    }

    public static function negate(value:Null<Float>):Float {
        if (value == null)
            return 0.0;
        return -value;
    }

    public static function accumulate(values:Array<Float>, raw:Null<Float>):Void {
        final amount = raw == null ? 0.0 : raw;
        values[0] += amount;
    }

    public static function describe(prefix:String, raw:Null<String>):String {
        final detail = raw == null ? "" : raw;
        return prefix + "-" + detail + ".";
    }

    public static function found(flag:Bool, holder:OptionalValueUseHolder):OptionalValueUseHolder {
        var result:Null<OptionalValueUseHolder> = null;
        if (flag)
            result = holder;
        return flag ? result : null;
    }
}
#else
class OptionalValueUseOps {}
#end
