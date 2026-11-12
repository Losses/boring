package boring;

/**
    The unmarked control of the variable form (features/10): the same
    `static final` without the marker keeps its holder namespace on every
    target. The instance member keeps this a class on Dart, whose
    statics-only flattening would otherwise move the constant to library
    scope.
**/
class HolderConstOps {
    public static final HOLDER_ISSUE:String = "HolderMember";

    public final id:Int;

    public function new(id:Int) {
        this.id = id;
    }

    public function issue():String {
        return HOLDER_ISSUE;
    }
}
