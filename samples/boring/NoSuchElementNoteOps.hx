package boring;

/**
    Reads the folded message off a payload-carrying single-variant
    exception value. Gated to Kotlin until every target lowers the
    capture-bound single-case switch (features/43).
**/
#if kotlin_output
class NoSuchElementNoteOps {
    public static function describe(note:NoSuchElementNote):String {
        return new NoSuchElementNoteException(note).message;
    }
}
#end
