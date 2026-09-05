package tests;

import boring.NoSuchElementFault;
import boring.NoSuchElementFaultException;
import boring.NoSuchElementMessageReader;
import boring.NoSuchElementNote;
import boring.NoSuchElementNoteOps;
import boring.NoSuchElementThrower;
import std.Test;

class NoSuchElementTests {
    @:test("a module-listed exception class that only a catch references stays emitted")
    public static function caught():Void {
        var text = "";
        try {
            NoSuchElementThrower.missing();
        } catch (error:NoSuchElementFaultException) {
            text = error.message;
        }
        Test.equals("no such element", text);
    }

    @:test("a message read off a folded exception value outside a catch lowers to the property")
    public static function messageRead():Void {
        final err = new NoSuchElementFaultException(NoSuchElementFault.Missing);
        Test.equals("no such element", NoSuchElementMessageReader.describe(err));
    }

    @:test("a folded exception reports its variant message text")
    public static function foldedVariantMessage():Void {
        #if kotlin_output
        Test.equals("gone", NoSuchElementNoteOps.describe(NoSuchElementNote.Note("gone")));
        #else
        Test.equals("no such element", new NoSuchElementFaultException(NoSuchElementFault.Missing).message);
        #end
    }
}
