package scp;

import std.Console;
import std.ReadOnlyArray;

/**
    Aliased read-only boundary cases. Several targets reject the transparent
    alias spelling in a parameter or return position, so these cases are
    generated separately. A blocked generation is recorded as the
    observation; no passing run stands in for the boundary.

    The expectation is at the source level: a transparent alias of
    the reserved read-only declaration names the same source face as its
    declaration.
**/
class CallerAliasBoundary {
    /** Static container through a transparent alias of the read-only face.
        The static initializer rules of feature 30 sanction an empty literal. */
    public static var table:BoundaryReadOnlyList<Int> = [];

    /** Iteration over a generic alias of the built-in array. */
    public static function sumBox():Int {
        final box:BoundaryBox<Int> = [1, 2, 3];
        var total = 0;
        for (item in box) {
            total += item;
        }
        return total;
    }

    /** Read-only parameter through a transparent alias. */
    public static function sumReadOnly(values:BoundaryReadOnlyList<Int>):Int {
        var total = 0;
        for (value in values) {
            total += value;
        }
        return total;
    }

    /** Read-only return through a transparent alias. */
    public static function names():BoundaryReadOnlyList<String> {
        return ["ann", "bo"];
    }

    public static function run():Void {
        Console.log('sumBox=${sumBox()} table=${table.length} names=${names()[0]}');
    }
}

/** Generic alias of the built-in mutable array, declared in CallerCases. */
typedef BoundaryBox<T> = scp.CallerCases.Box<T>;

/** Generic alias of the reserved read-only declaration. */
typedef BoundaryReadOnlyList<T> = ReadOnlyArray<T>;
