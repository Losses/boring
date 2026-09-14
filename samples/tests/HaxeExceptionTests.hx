package tests;

import std.Test;

#if (rust_output || swift_output || dart_output || kotlin_output)
import boring.HaxeExceptionOps.HaxeExceptionFault;
import boring.HaxeExceptionOps;
#end

class HaxeExceptionTests {
    @:test("haxe.Exception subclasses preserve message values when thrown and caught")
    public static function thrownMessage():Void {
        #if (rust_output || swift_output || dart_output || kotlin_output)
        var message = "haxe exception message";
        var caught = "";
        try {
            HaxeExceptionOps.throwFault(message);
        } catch (error:HaxeExceptionFault) {
            caught = error.message;
        }
        Test.equals(message, caught);
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a concatenated exception message crosses the constructor as a str view")
    public static function joinedMessage():Void {
        #if (rust_output || swift_output || dart_output || kotlin_output)
        var caught = "";
        try {
            HaxeExceptionOps.throwJoined("ab", "cd");
        } catch (error:HaxeExceptionFault) {
            caught = error.message;
        }
        Test.equals("abcd", caught);
        #else
        Test.equals(true, true);
        #end
    }
}
