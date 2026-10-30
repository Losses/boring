package rusthandlefixtures;

// closure capture: a local closure captures a handle.
class Counter {
    public var value:Int;
    public function new() {
        value = 0;
    }

    public function inc():Int {
        value += 1;
        return value;
    }
}

class ClosureCaptureOps {
    public static function run():Int {
        final counter = new Counter();
        final step = function() return counter.inc();
        return step();
    }
}
