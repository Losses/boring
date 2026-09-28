package flow.normalized;

/**
    One nullable instance used by the normalized flow cases. A field read on a
    nullable receiver is the instrumented use: its only target decision is the
    separator, so an emitted difference between a case and its control comes
    from the presence decision and not from a member spelling.
**/
class Cell {
    public var width:Int;

    public function new(width:Int) {
        this.width = width;
    }
}
