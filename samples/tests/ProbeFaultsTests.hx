package tests;

import boring.ProbeFaults;
import std.Test;

class ProbeFaultsTests {
    @:test("exception parameters are accepted")
    public static function note():Void {
        Test.equals("none", ProbeFaults.note());
    }
}
