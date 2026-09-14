package tests;

import boring.M2OptionVecOps;
import boring.GuardedBox;
import boring.GuardedRect;
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

    @:test("Vec and String indexOf compared against -1 share the signed domain")
    public static function indexOfCompared():Void {
        #if rust_output
        Test.equals(true, M2OptionVecOps.hasIndex(["a", "b"], "b"));
        Test.equals(false, M2OptionVecOps.hasIndex(["a", "b"], "z"));
        Test.equals(true, M2OptionVecOps.hasTextIndex("abc", "b"));
        Test.equals(false, M2OptionVecOps.hasTextIndex("abc", "z"));
        #end
    }

    @:test("guarded-copy local reads fields of the proven inner value")
    public static function guardedCopyLocal():Void {
        #if rust_output
        Test.equals(true, M2OptionVecOps.guardedCopyWidth(new GuardedRect(1.5, 2.5)) == 4.0);
        Test.equals(true, M2OptionVecOps.guardedCopyWidth(null) == 0.0);
        final box = new GuardedBox();
        Test.equals(true, M2OptionVecOps.guardedCopyFieldWidth(box) == 0.0);
        box.rect = new GuardedRect(3.0, 4.0);
        Test.equals(true, M2OptionVecOps.guardedCopyFieldWidth(box) == 7.0);
        #end
    }

    @:test("guarded and-chain reads fields of the proven inner value")
    public static function guardedAndChain():Void {
        #if rust_output
        Test.equals(true, M2OptionVecOps.guardedAndSpan(new GuardedRect(1.5, 2.5), 2.0) == 2.5);
        Test.equals(true, M2OptionVecOps.guardedAndSpan(new GuardedRect(5.0, 2.5), 2.0) == 0.0);
        Test.equals(true, M2OptionVecOps.guardedAndSpan(null, 2.0) == 0.0);
        #end
    }

    @:test("guarded holder field copies the proven inner value")
    public static function guardedHolderField():Void {
        #if rust_output
        final box = new GuardedBox();
        Test.equals(true, M2OptionVecOps.guardedHolderSpan(box) == 0.0);
        box.rect = new GuardedRect(3.0, 4.0);
        Test.equals(true, M2OptionVecOps.guardedHolderSpan(box) == 7.0);
        #end
    }
}