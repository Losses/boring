package boring;

#if swift_output
@:dataClass
class GlobalThrowBox {
    public final value:Int;

    public function new(value:Int) {
        if (value < 0) {
            throw new ValueException(NegativeStart);
        }
        this.value = value;
    }
}

/**
 * A stored static initializer cannot throw in Swift, and a computed
 * property accessor cannot rethrow; both force the fault at the
 * declaration because the initializer is a compile-time fixture.
 */
class SwiftGlobalThrowOps {
    public static final seed:GlobalThrowBox = new GlobalThrowBox(3);

    public var current(get, never):GlobalThrowBox;

    public function new() {}

    function get_current():GlobalThrowBox {
        return new GlobalThrowBox(seed.value + 1);
    }

    public static function seedValue():Int {
        return seed.value;
    }

    public static function currentValue(ops:SwiftGlobalThrowOps):Int {
        return ops.current.value;
    }
}
#else
class SwiftGlobalThrowOps {}
#end
