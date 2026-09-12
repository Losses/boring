package boring;

/**
    A message-only child delegating through the folded parent payload,
    so the sealed fold keeps the super-delegation message-typed
    (features/06). Gated to Kotlin with the parent shape it covers.
**/
#if kotlin_output
class SealedChildException extends SealedChildParent {
    public function new(message:String) {
        super(Note(message));
    }
}
#else
class SealedChildException {}
#end
