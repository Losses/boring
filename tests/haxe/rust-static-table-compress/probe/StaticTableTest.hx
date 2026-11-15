package probe;

class StaticTableProbeFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}

class StaticTableTest {
    @:test
    public static function readsTable():Void {
        final v = StaticTable.VALUES;
        if (v.length != 300) throw new StaticTableProbeFault("bad length");
    }
}
