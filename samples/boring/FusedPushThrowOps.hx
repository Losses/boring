package boring;

#if swift_output
@:dataClass
class FusedPushItem {
    public final value:Int;

    public function new(value:Int) {
        if (value < 0) {
            throw new ValueException(NegativeStart);
        }
        this.value = value;
    }
}

/**
 * Counted fill loops lower to reserveCapacity plus one append per step.
 * When the appended value construction throws, the append still needs
 * the try marker; the fused emitter path must add it exactly like the
 * generic statement path.
 */
class FusedPushThrowOps {
    public static function build(values:Array<Int>):Array<FusedPushItem> {
        final result = new Array<FusedPushItem>();
        for (i in 0...values.length) {
            result.push(new FusedPushItem(values[i]));
        }
        return result;
    }

    public static function total(values:Array<Int>):Int {
        final items = build(values);
        var sum = 0;
        for (item in items) {
            sum += item.value;
        }
        return sum;
    }
}
#else
class FusedPushThrowOps {}
#end
