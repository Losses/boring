package coercereceiver;

/**
    Receiver coercion probe for P2.5.

    Three receiver access forms, one per method, each proven against the
    real guard/smart-cast chain:

    * readFinal  -- a final nullable receiver null-guarded then read:
                    the field proof plus smart-castability (FVar + isFinal)
                    holds, so the access stays a plain ".".
    * readVar    -- a var nullable receiver null-guarded then read:
                    the proof registers but Kotlin never smart-casts a
                    mutable property (fieldPropertyStable fails on !isFinal),
                    so the access hardens with "!!.".
    * readUnproven -- a nullable parameter receiver read without any guard:
                    the access stays a safe-call "?.".

    Without the Receiver coercion the member-access operator (".", "?.") is
    dropped, leaving receiverfield text that kotlinc rejects.
**/
class ReceiverCases {
    /** Nullable final receiver: smart-casts, reads with ".". */
    public final finalChild:Null<ReceiverCases>;

    /** Nullable var receiver: never smart-casts, reads with "!!.". */
    public var varChild:Null<ReceiverCases>;

    /** Nullable field target: a nullable receiver reads it with "?.". */
    public var label:Null<String>;

    public function new() {
        this.finalChild = null;
        this.varChild = null;
        this.label = null;
    }

    /** Proven val receiver -> ".". */
    public function readFinal():Null<String> {
        if (this.finalChild != null)
            return this.finalChild.label;
        return null;
    }

    /** Proven non-smart-cast var receiver -> "!!.". */
    public function readVar():Null<String> {
        if (this.varChild != null)
            return this.varChild.label;
        return null;
    }

    /** Unproven nullable receiver -> "?.". */
    public function readUnproven(value:Null<ReceiverCases>):Null<String> {
        return value.label;
    }
}
