package tests;

import boring.NullableArrayOps;
import std.Test;

class NullableArrayTests {
    @:test("nullable Int array literals keep every element")
    public static function nullableIntLiterals():Void {
        final arr = NullableArrayOps.literalMixed();
        Test.equals(3, arr.length);
        Test.equals(true, NullableArrayOps.elementMatches(arr, 0, 1));
        Test.equals(true, NullableArrayOps.elementMatches(arr, 1, null));
        Test.equals(true, NullableArrayOps.elementMatches(arr, 2, 3));
    }

    @:test("a single null element stays null")
    public static function singleNull():Void {
        final arr = NullableArrayOps.literalSingleNull();
        Test.equals(1, arr.length);
        Test.equals(true, NullableArrayOps.elementMatches(arr, 0, null));
    }

    @:test("nullable variables pass through without Some wrapping")
    public static function nullableVarElements():Void {
        final withValue = NullableArrayOps.fromNullableVar(9);
        Test.equals(3, withValue.length);
        Test.equals(true, NullableArrayOps.elementMatches(withValue, 0, 9));
        Test.equals(true, NullableArrayOps.elementMatches(withValue, 1, 5));
        Test.equals(true, NullableArrayOps.elementMatches(withValue, 2, null));
        final withNull = NullableArrayOps.fromNullableVar(null);
        Test.equals(true, NullableArrayOps.elementMatches(withNull, 0, null));
    }

    @:test("nullable String array literals keep every element")
    public static function nullableStringLiterals():Void {
        final arr = NullableArrayOps.nullableStrings();
        Test.equals(3, arr.length);
        Test.equals(true, NullableArrayOps.stringElementMatches(arr, 0, "a"));
        Test.equals(true, NullableArrayOps.stringElementMatches(arr, 1, null));
        Test.equals(true, NullableArrayOps.stringElementMatches(arr, 2, "c"));
    }
}
