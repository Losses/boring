package probe;

class StaticTableFallbackTest {
    @:test
    public static function readsTable():Void {
        final v = StaticTableFallback.VALUES;
        if (v.length != 300) throw "bad length";
    }
}
