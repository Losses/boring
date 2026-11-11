package probe;

// A null-initialized mutable class static, re-assigned to a fresh object on
// every iteration. This is the shape that discriminates the loop-condition
// static-read hoist: the condition must re-read the static each iteration.
class ReassignCounter {
    public var value:Int;

    public function new(value:Int) {
        this.value = value;
    }
}

class ReassignLoop {
    public static var INSTANCE:ReassignCounter = null;

    public static function run():Int {
        INSTANCE = new ReassignCounter(3);
        var steps = 0;
        while (INSTANCE.value > 0 && INSTANCE.value < 10) {
            INSTANCE = new ReassignCounter(INSTANCE.value - 1);
            steps += 1;
            if (steps > 100) {
                return steps;
            }
        }
        return steps * 100 + INSTANCE.value;
    }

    public static function currentValue():Int {
        return INSTANCE == null ? 999 : INSTANCE.value;
    }
}
