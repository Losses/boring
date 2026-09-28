package scp;

import std.Console;
import std.ReadOnlyArray;

/**
    Authored cases that reach the production callers of the three container
    queries with direct written forms only: interception iteration, pipeline
    iteration, and the target static declaration and return boundaries.

    Every alias spelling lives in `CallerAliasBoundary`, because several
    targets reject a transparent alias in declaration, parameter, return, and
    even local positions. Keeping the alias cases in one separately generated
    module lets the direct forms produce a full five-target comparison while
    the blocked alias generations are recorded as the observation they are.
**/
class CallerCases {
    /** Static container in the direct built-in form. The static initializer
        rules of feature 30 sanction an empty literal. */
    public static var directTable:Array<Int> = [];

    /** Iteration over the direct built-in array. */
    public static function sumDirect():Int {
        final direct:Array<Int> = [1, 2, 3];
        var total = 0;
        for (item in direct) {
            total += item;
        }
        return total;
    }

    /** Read-only parameter in the direct form. */
    public static function sumReadOnlyDirect(values:ReadOnlyArray<Int>):Int {
        var total = 0;
        for (value in values) {
            total += value;
        }
        return total;
    }

    /** Read-only return in the direct form. */
    public static function namesDirect():ReadOnlyArray<String> {
        return ["ann", "bo"];
    }

    public static function run():Void {
        Console.log('sumDirect=${sumDirect()}');
        Console.log('sumReadOnlyDirect=${sumReadOnlyDirect(directTable)}');
        Console.log('names=${namesDirect()[0]}${namesDirect()[1]}');
    }
}

/** Generic alias of the built-in mutable array, used by the alias module. */
typedef Box<T> = Array<T>;

/** Generic alias of the reserved read-only declaration, used by the alias module. */
typedef ReadOnlyList<T> = ReadOnlyArray<T>;
