package tests.haxe.rustGatedValueCopy;

import rustcompiler.GatedValueCopy;

/**
    Pure assertions for the gated-value-copy judgment: compile and run
    with haxe alone, no generation and no cargo.

    Run from the boring root:
      /nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe \
        -cp packages/compiler -cp tests -x tests.haxe.rustGatedValueCopy.GatedValueCopyAssertions
    Exit code 0 = all pass.
*/
class GatedValueCopyAssertions {
    static var failures = 0;

    static function expect(expected:Bool, actual:Bool, label:String):Void {
        if (expected == actual)
            Sys.println("PASS " + label);
        else {
            failures++;
            Sys.println("FAIL " + label + " expected=" + expected + " actual=" + actual);
        }
    }

    public static function main() {
        // Handle forms: not a value copy.
        expect(true, GatedValueCopy.renderedIsHandleForm("Rc::clone(&worker)"), "rc clone is a handle");
        expect(true, GatedValueCopy.renderedIsHandleForm("EscapingWorkerA::new()"), "constructor is a handle");
        expect(true, GatedValueCopy.renderedIsHandleForm("Rc::new(RefCell::new(worker))"), "wrapped slot is a handle");
        // Value copies: bare names and unknown text fail closed.
        expect(false, GatedValueCopy.renderedIsHandleForm("worker"), "bare name is not a handle form");
        expect(false, GatedValueCopy.renderedIsHandleForm(""), "empty text is not a handle form");
        expect(true, GatedValueCopy.isValueCopy(true, "worker"), "gated bare name is a value copy");
        expect(true, GatedValueCopy.isValueCopy(true, ""), "gated empty text fails closed as a value copy");
        expect(false, GatedValueCopy.isValueCopy(true, "Rc::clone(&worker)"), "gated handle clone is not a value copy");
        expect(false, GatedValueCopy.isValueCopy(true, "EscapingWorkerA::new()"), "gated constructor is not a value copy");
        expect(false, GatedValueCopy.isValueCopy(true, "Rc::new(RefCell::new(worker))"), "gated wrapped slot is not a value copy");
        // A non-gated class is never flagged.
        expect(false, GatedValueCopy.isValueCopy(false, "worker"), "non-gated class is never a value copy");
        if (failures > 0)
            Sys.exit(1);
        Sys.println("ALL PASS");
    }
}
