package coercearg;

/**
    Argument coercion probe for P2.4.

    nullableFirstArg hardens a nullable StringTools.trim receiver with "!!"
    because the callee parameter is non-null (an Any? parameter would admit
    absence and pass the null through; a String parameter does not). Without
    the coercion the emitter leaves s.trim() with s: String?, which Kotlin
    rejects as a nullable-receiver call.
**/
class ArgCases {
    /** Nullable trim receiver: emits s!!.trim() in the positive tree. */
    public function trimmed(s:Null<String>):String {
        return StringTools.trim(s);
    }
}
