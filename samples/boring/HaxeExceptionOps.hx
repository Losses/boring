package boring;

#if (rust_output || swift_output || dart_output || kotlin_output)
class HaxeExceptionOps {
    public static function throwFault(message:String):Void {
        throw new HaxeExceptionFault(message);
    }

    public static function throwJoined(lead:String, tail:String):Void {
        throw new HaxeExceptionFault(lead + tail);
    }

    // A direct message-only throw and a callee throw from another
    // message-only class meet in one synthetic union. The direct throw
    // wraps into its member variant so the Err payload matches the union
    // Result type.
    #if rust_output
    public static function throwMixed(value:String):Void {
        if (value.length == 0)
            throw new HaxeExceptionFault("direct");
        BorrowedStringReturnOps.requireText(value);
    }
    #end
}

class HaxeExceptionFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}
#else
class HaxeExceptionOps {}
#end
