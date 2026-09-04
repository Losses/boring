package tests;

import boring.Int64Ops;
import std.Test;
import haxe.Int64;

class Int64Tests {
    @:test("constructs and extracts 64-bit words")
    public static function construction():Void {
        final value = Int64.make(0x12345678, -1698898192);
        Test.equals(0x12345678, Int64Ops.high(value));
        Test.equals(-1698898192, Int64Ops.low(value));
    }

    @:test("wraps addition across the low word")
    public static function carry():Void {
        final value = Int64Ops.carry();
        Test.equals(1, Int64Ops.high(value));
        Test.equals(0, Int64Ops.low(value));
    }

    @:test("wraps Int64 multiplication")
    public static function multiplication():Void {
        final value = Int64Ops.mulAnchors();
        Test.equals(0xDEF35B01, Int64Ops.high(value));
        Test.equals(0x0F796CA9, Int64Ops.low(value));
        final negative = Int64.mul(Int64.make(-1, -1), Int64.make(-1, -1));
        Test.equals(0, Int64Ops.high(negative));
        Test.equals(1, Int64Ops.low(negative));
        final mixed = Int64Ops.mulIntAnchor(Int64.make(0, 5));
        Test.equals(0, Int64Ops.high(mixed));
        Test.equals(15, Int64Ops.low(mixed));
        final direct = Int64.mul(Int64.make(0, 3), Int64.make(0, 5));
        Test.equals(0, Int64Ops.high(direct));
        Test.equals(15, Int64Ops.low(direct));
    }

    @:test("compares signed Int64 values at limits and across zero")
    public static function ordering():Void {
        final negative = Int64.ofInt(-1);
        final zero = Int64.ofInt(0);
        final equal = Int64.ofInt(7);
        final maximum = Int64.make(0x7FFFFFFF, -1);
        final minimum = Int64.make(-2147483648, 0);
        Test.equals(true, Int64Ops.below(negative, zero));
        Test.equals(true, Int64Ops.atOrBelow(equal, equal));
        Test.equals(true, equal >= equal);
        Test.equals(true, Int64Ops.below(minimum, maximum));
        Test.equals(true, maximum >= minimum);
        Test.equals(true, maximum > minimum);
        Test.equals(true, Int64Ops.below(negative, zero));
        Test.equals(true, zero <= zero);
    }

    @:test("keeps rotate and bitwise operations at 64 bits")
    public static function operations():Void {
        final value = Int64.make(0x12345678, -1698898192);
        final rotated = Int64Ops.rotate(value, 32);
        Test.equals(-1698898192, Int64Ops.high(rotated));
        Test.equals(0x12345678, Int64Ops.low(rotated));
        final mixed = Int64Ops.bitMix(value);
        Test.equals(-1197540142, Int64Ops.high(mixed));
        Test.equals(-806777947, Int64Ops.low(mixed));
    }
}
