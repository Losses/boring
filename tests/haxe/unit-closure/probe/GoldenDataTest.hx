package probe;

/** @:test module that references GoldenData, making it test-only. */
class GoldenDataTest {
    @:test
    public static function readsGolden():Void {
        final d = new GoldenData(7);
        final v:Int = d.value;
    }
}
