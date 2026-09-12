package boring;

/**
    Reads the message of a message-only child through its folded parent
    type. Gated to Kotlin with the exception shape it covers.
**/
#if kotlin_output
class SealedChildOps {
    public static function describe(error:SealedChildParent):String {
        return error.message;
    }

    public static function childMessage(message:String):String {
        return describe(new SealedChildException(message));
    }
}
#else
class SealedChildOps {}
#end
