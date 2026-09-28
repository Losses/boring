package closureFixture;

import std.Test;

class ClosureTests {
    @:test
    public static function testArrayRuntimeIsAvailable():Void {
        Test.equals(5, Main.observedValue());
    }
}
