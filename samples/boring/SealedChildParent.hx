package boring;

/**
    The folded parent of the sealed-child shape. Gated to Kotlin until
    every target lowers the capture-bound single-case switch in
    `describe` (features/43).
**/
#if kotlin_output
class SealedChildParent extends haxe.Exception {
    public final cause:SealedChildCause;

    public function new(cause:SealedChildCause) {
        this.cause = cause;
        super(SealedChildParent.describe(cause));
    }

    public static function describe(cause:SealedChildCause):String {
        return switch (cause) {
            case Note(text): text;
        };
    }
}
#else
class SealedChildParent {}
#end
