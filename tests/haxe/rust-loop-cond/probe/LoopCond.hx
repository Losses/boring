package probe;

class LoopCounter {
    public var value:Int;

    public function new(value:Int) {
        this.value = value;
    }

    public function decrement():Void {
        value = value - 1;
    }
}

class LoopCond {
    public static final INSTANCE:LoopCounter = new LoopCounter(3);

    public static function run():Void {
        var guard = 0;
        while (INSTANCE.value > 0 && INSTANCE.value < 10) {
            INSTANCE.decrement();
            guard += 1;
            if (guard > 100) {
                break;
            }
        }
    }
}
