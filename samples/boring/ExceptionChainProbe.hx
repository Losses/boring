package boring;

#if kotlin_output
class ExceptionChainProbe {
    public static function previousMessage(cause:Null<haxe.Exception>):String {
        if (cause == null) {
            return "none";
        }
        final prev = cause.previous;
        return prev == null ? "none" : prev.message;
    }
}
#else
class ExceptionChainProbe {}
#end