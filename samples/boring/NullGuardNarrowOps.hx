package boring;

#if swift_output
/**
    A nullable local proven non-null by `x != null` stays nullable in
    Haxe's type, so the Swift value use needs the force unwrap: inside the
    right operand of `&&`, inside the guarded block, and in the non-nil arm
    of a ternary. A local assigned from a guarded member path narrows too.
*/
class NullGuardNarrowOps {
    public static function at(xs:Array<Int>, index:Null<Int>):Int {
        if (index != null && xs[index] > 0)
            return xs[index];
        return -1;
    }

    public static function both(xs:Array<Int>, a:Null<Int>, b:Null<Int>):Int {
        if (a != null && b != null && xs[a] < xs[b])
            return xs[a] + xs[b];
        return -2;
    }

    public static function earlyReturn(xs:Array<Int>, index:Null<Int>):Int {
        if (index == null)
            return -3;
        return xs[index];
    }

    public static function fromHolder(xs:Array<Int>, holder:NullGuardNarrowHolder):Int {
        if (holder.index == null)
            return -4;
        final index = holder.index;
        return xs[index];
    }

    public static function pick(xs:Array<Int>, index:Null<Int>):Int {
        return index == null ? -5 : xs[index];
    }
}
#else
class NullGuardNarrowOps {}
#end
