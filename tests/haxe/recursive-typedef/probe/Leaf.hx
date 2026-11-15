package probe;

/** Non-recursive dependency of DiagRec: its module must stay in the walk. */
class Leaf {
    public final code:Int;

    public function new(code:Int) {
        this.code = code;
    }
}
