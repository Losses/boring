package tests;

import std.Test;

/**
 * A helper class shared across test modules. Lives beside the test
 * modules so a peer test module can import it and resolve it from
 * the business output directory.
 **/
class ProbeShareTests {
    public static function sharedLabel(): String {
        return "shared";
    }
}

/**
 * Test module that exercises the shared helper import.
 **/
class ProbeShareTestsModule {
    @:test("shared probe module compiles")
    public static function probe(): Void {
        Test.equals("shared", ProbeShareTests.sharedLabel());
    }
}
