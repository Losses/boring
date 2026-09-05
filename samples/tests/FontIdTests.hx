package tests;

import boring.FontIdConsumer;
import std.Test;

/** The cross-module static of a sub-type abstract emits its Impl_ object. */
class FontIdTests {
    @:test("a non-inline static on a sub-type abstract is callable across modules")
    public static function make():Void {
        Test.equals(true, FontIdConsumer.isPrefixed("hello"));
    }
}
