package tests;

import boring.M2OptionVecOps;
import std.Test;

class M2OptionVecTests {
    @:test("nullable array receiver pushes and joins")
    public static function nullableArrayReceiver():Void {
        #if rust_output
        var ops = new M2OptionVecOps();
        ops.tags = null;
        Test.equals("a", ops.addTag("a"));
        Test.equals("a,b", ops.addTag("b"));
        #end
    }

    @:test("nullable sorted set receiver queries membership")
    public static function nullableSetReceiver():Void {
        #if rust_output
        var ops = new M2OptionVecOps();
        ops.seen = null;
        Test.equals(false, ops.hasSeen(5));
        Test.equals(0, ops.countSeen());
        #end
    }

    @:test("nullable sorted map receiver reads a stored value")
    public static function nullableMapReceiver():Void {
        #if rust_output
        var ops = new M2OptionVecOps();
        ops.index = null;
        Test.equals(true, ops.readIndex(7));
        #end
    }

    @:test("Vec copy clones the array")
    public static function vecCopy():Void {
        #if rust_output
        Test.equals("1,2,3", M2OptionVecOps.copyArray(["1", "2", "3"]));
        #end
    }

    @:test("Vec shift removes the first element")
    public static function vecShift():Void {
        #if rust_output
        Test.equals("1:2,3", M2OptionVecOps.shiftArray(["1", "2", "3"]));
        #end
    }

    @:test("Vec unshift inserts at the front")
    public static function vecUnshift():Void {
        #if rust_output
        Test.equals("9,1,2", M2OptionVecOps.unshiftArray(["1", "2"], "9"));
        #end
    }

    @:test("Vec indexOf finds the element position")
    public static function vecIndexOf():Void {
        #if rust_output
        Test.equals("1", M2OptionVecOps.indexOfArray(["a", "b", "c"], "b"));
        Test.equals("-1", M2OptionVecOps.indexOfArray(["a", "b", "c"], "z"));
        #end
    }
}