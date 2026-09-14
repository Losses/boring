package boring;

#if (rust_output || swift_output || dart_output || kotlin_output)
class HaxeExceptionOps {
    public static function throwFault(message:String):Void {
        throw new HaxeExceptionFault(message);
    }

    public static function throwJoined(lead:String, tail:String):Void {
        throw new HaxeExceptionFault(lead + tail);
    }
}

class HaxeExceptionFault extends haxe.Exception {
    public function new(message:String) {
        super(message);
    }
}
#else
class HaxeExceptionOps {}
#end
