package boring;

#if swift_output
/**
    `Math.min`/`Math.max` lower to an immediately-invoked closure that
    binds its two widened operands. A Haxe local named `a` (or `b`) in an
    operand is evaluated at the call site so the closure stays shadow-free.
*/
class MinShadowItem {
    public final reduction:Float;

    public function new(reduction:Float)
        this.reduction = reduction;
}

class MathMinShadowOps {
    public static function make(reduction:Float):MinShadowItem
        return new MinShadowItem(reduction);

    public static function clamp(items:Array<MinShadowItem>, limit:Float):Float {
        var total = 0.0;
        for (a in items)
            total += Math.min(limit, total + a.reduction);
        return total;
    }
}
#else
class MathMinShadowOps {}
#end
