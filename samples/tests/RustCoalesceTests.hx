package tests;

import boring.RustCoalesceOps;
import std.Test;

class RustCoalesceTests {
    @:test("nullable class coalescing materializes optional constructor arguments")
    public static function defaultRecord():Void {
        Test.equals("zh-Hans:16:400:false:0", RustCoalesceOps.resolve());
    }
}
