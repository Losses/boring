package tests;

import std.Test;

#if swift_output
import boring.NullGuardNarrowOps;
import boring.NullGuardNarrowHolder;
#end

class NullGuardNarrowTests {
    @:test("a null guard narrows the value use in Swift")
    public static function testNarrowing():Void {
        #if swift_output
        final xs = [3, 1, 2];
        Test.equals(3, NullGuardNarrowOps.at(xs, 0));
        Test.equals(-1, NullGuardNarrowOps.at(xs, null));
        Test.equals(4, NullGuardNarrowOps.both(xs, 1, 0));
        Test.equals(-2, NullGuardNarrowOps.both(xs, null, 1));
        Test.equals(2, NullGuardNarrowOps.earlyReturn(xs, 2));
        Test.equals(-3, NullGuardNarrowOps.earlyReturn(xs, null));
        Test.equals(1, NullGuardNarrowOps.fromHolder(xs, new NullGuardNarrowHolder(1)));
        Test.equals(-4, NullGuardNarrowOps.fromHolder(xs, new NullGuardNarrowHolder(null)));
        Test.equals(2, NullGuardNarrowOps.pick(xs, 2));
        Test.equals(-5, NullGuardNarrowOps.pick(xs, null));
        #else
        Test.equals(true, true);
        #end
    }
}
