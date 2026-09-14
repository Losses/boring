package tests;

import boring.RustCoalesceOps;
import std.Test;

class RustCoalesceTests {
    @:test("a coalescing nullable array parameter copies a direct array static")
    public static function directArrayStatic():Void {
        Test.equals(3, RustCoalesceOps.resolvedInts());
    }

    @:test("nullable class coalescing materializes optional constructor arguments")
    public static function defaultRecord():Void {
        Test.equals("zh-Hans:16:400:false:0", RustCoalesceOps.resolve());
        #if rust_output
        Test.equals("zh-Hans", RustCoalesceOps.rustOutputStringDefault());
        #end
    }
}
