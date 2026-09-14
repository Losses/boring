package tests;

import boring.RustCoalesceOps;
import std.Test;

class RustCoalesceTests {
    @:test("a coalescing nullable array parameter copies a direct array static")
    public static function directArrayStatic():Void {
        Test.equals(3, RustCoalesceOps.resolvedInts());
    }

    @:test("a nullable String field assignment owns a borrowed view")
    public static function assignedStringField():Void {
        Test.equals(true, RustCoalesceOps.assignedLabel("tone"));
    }

    @:test("an omitted nullable String parameter owns the substituted view")
    public static function substitutedStringDefault():Void {
        Test.equals("tone", RustCoalesceOps.displayDefault("tone"));
    }

    @:test("a coalescing nullable String parameter owns a borrowed view")
    public static function borrowedStringDefault():Void {
        Test.equals("fr-FR", RustCoalesceOps.localeFrom("fr-FR"));
    }

    @:test("nullable class coalescing materializes optional constructor arguments")
    public static function defaultRecord():Void {
        Test.equals("zh-Hans:16:400:false:0", RustCoalesceOps.resolve());
        #if rust_output
        Test.equals("zh-Hans", RustCoalesceOps.rustOutputStringDefault());
        #end
    }
}
