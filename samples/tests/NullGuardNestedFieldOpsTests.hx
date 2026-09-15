package tests;

import boring.NullGuardNestedFieldOps;
#if rust_output
import boring.NullGuardNestedFieldOps.NullGuardNestedHolder;
import boring.NullGuardNestedFieldOps.NullGuardNestedSpan;
#end
import std.Test;

class NullGuardNestedFieldOpsTests {
    @:test("a guarded local reads through an intermediate member")
    public static function startsBefore():Void {
        #if rust_output
        final holder = new NullGuardNestedHolder(new NullGuardNestedSpan(2.0, 4.0));
        Test.equals(true, NullGuardNestedFieldOps.startsBefore(holder, 3.0));
        Test.equals(false, NullGuardNestedFieldOps.startsBefore(holder, 1.0));
        Test.equals(false, NullGuardNestedFieldOps.startsBefore(null, 3.0));
        #end
    }

    @:test("two guarded paths compare through their intermediate members")
    public static function matchingSpan():Void {
        #if rust_output
        final holder = new NullGuardNestedHolder(new NullGuardNestedSpan(2.0, 4.0));
        final same = new NullGuardNestedHolder(new NullGuardNestedSpan(2.0, 9.0));
        final other = new NullGuardNestedHolder(new NullGuardNestedSpan(1.0, 4.0));
        Test.equals(true, NullGuardNestedFieldOps.matchingSpan(holder, same));
        Test.equals(false, NullGuardNestedFieldOps.matchingSpan(holder, other));
        #end
    }

    @:test("a guarded local returns a value read through an intermediate member")
    public static function spanLeft():Void {
        #if rust_output
        final holder = new NullGuardNestedHolder(new NullGuardNestedSpan(2.0, 4.0));
        Test.equals(true, NullGuardNestedFieldOps.spanLeft(holder) == 2.0);
        Test.equals(true, NullGuardNestedFieldOps.spanLeft(new NullGuardNestedHolder(new NullGuardNestedSpan(12.0, 4.0))) == 0.0);
        Test.equals(true, NullGuardNestedFieldOps.spanLeft(null) == 0.0);
        #end
    }
}
