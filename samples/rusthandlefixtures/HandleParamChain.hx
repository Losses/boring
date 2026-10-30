package rusthandlefixtures;

// handle param chain: an owned handle param drives multiple instance method
// calls (mutate then read); the handle must be borrowed per call, never moved
// into the first call.
class Counter {
    public var value:Int;
    public function new() { value = 0; }
    public function inc():Void { value += 1; }
    public function read():Int return value;
}

class HandleParamChainOps {
    public static function run(c:Counter):Int {
        c.inc();
        c.inc();
        return c.read();
    }
}
