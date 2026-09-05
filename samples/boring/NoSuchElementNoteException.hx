package boring;

/**
    A second folded exception, so the fold stays correct when two folded
    exceptions share a package. Gated to Kotlin until every target lowers
    the capture-bound single-case switch in `describe` (features/43).
**/
#if kotlin_output
class NoSuchElementNoteException extends haxe.Exception {
    public final note:NoSuchElementNote;

    public function new(note:NoSuchElementNote) {
        this.note = note;
        super(describe(note));
    }

    public static function describe(note:NoSuchElementNote):String {
        return switch (note) {
            case Note(text): text;
        };
    }
}
#end
