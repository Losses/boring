package tests;

import boring.ExceptionCatchOps;
import tests.ProbeShareTests;
import std.Test;

/**
 * Exercises two TS-specific import shapes:
 * 1. A `Null<haxe.Exception>` parameter type and `.message` access
 *    must lower to `Error | null` and `.message` without a stray
 *    import for the Haxe extern.
 * 2. A test module importing another test module must resolve the
 *    sibling via the test output directory and `*.test.ts` suffix.
 **/
class ExceptionCatchTests {
    @:test("haxe.Exception type lowers to Error")
    public static function exceptionTypeLowering(): Void {
        Test.equals("none", ExceptionCatchOps.causeMessage(null));
    }

    @:test("test module probes resolve across test files")
    public static function testModuleImport(): Void {
        Test.equals("shared", ProbeShareTests.sharedLabel());
    }
}
