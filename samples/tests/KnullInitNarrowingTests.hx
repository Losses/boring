package tests;

import boring.KnullInitNarrowing;
import std.Test;

class KnullInitNarrowingTests {
    @:test("reads a field off a nullable receiver bound to a non-null local")
    public static function fieldOffNullableReceiver():Void {
        final k = new KnullInitNarrowing();
        final nested = new boring.KnullInitNarrowing.Nested(5);
        Test.equals(5, k.fieldOffNullableReceiver(nested));
    }

    @:test("binds a non-null local from a ternary whose else arm is nullable")
    public static function ternaryWithNullableArm():Void {
        final k = new KnullInitNarrowing();
        Test.equals(1, k.ternaryWithNullableArm(true, null));
    }

    @:test("chains two field accesses off a nullable receiver")
    public static function chainedFieldAccess():Void {
        final k = new KnullInitNarrowing();
        final nested = new boring.KnullInitNarrowing.Nested(7);
        Test.equals("v7", k.chainedFieldAccess(nested));
    }
}
