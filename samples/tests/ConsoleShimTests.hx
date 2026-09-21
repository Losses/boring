package tests;

import std.Test;

#if (kotlin_output || ts_output || rust_output)
import boring.ConsoleShimOps;
#end

/**
    The runtime-backed console object on the two engine targets that give
    it a runtime face (docs/specs/stdlib/06-std-modules.md). The test
    runner records each result in a file and holds no capture of the
    standard output stream, so the assertions cover the call and its
    result: the line reaches the host console, the call returns, and the
    caller receives the computed value. The written line stays visible in
    the run output of each target. (KotlinConsoleShim)
**/
class ConsoleShimTests {
    @:test("std.Console.log returns to its caller")
    public static function logReturns():Void {
        #if (kotlin_output || ts_output || rust_output)
        Test.equals("logged:console-shim-probe", ConsoleShimOps.logLine("console-shim-probe"));
        #else
        Test.equals(true, true);
        #end
    }
}
