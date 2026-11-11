package probe;

class StaticTableTest {
    @:test
    public static function readsTable():Void {
        final v = StaticTable.VALUES;
        if (v.length != 300) throw "bad length";
    }
}
