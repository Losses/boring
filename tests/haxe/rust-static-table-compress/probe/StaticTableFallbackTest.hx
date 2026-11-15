package probe;

class StaticTableFallbackProbeFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}

class StaticTableFallbackTest {
    @:test
    public static function readsTable():Void {
        final v = StaticTableFallback.VALUES;
        if (v.length != 300) throw new StaticTableFallbackProbeFault("bad length");
    }
}
