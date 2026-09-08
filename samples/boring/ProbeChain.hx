package boring;

class ProbeChain {
    public final parent:Null<ProbeChain>;
    public final tag:Int;

    public function new(?parent:Null<ProbeChain>, tag:Int) {
        this.parent = parent;
        this.tag = tag;
    }

    public function depth():Int {
        final p = parent;
        if (p == null) {
            return 0;
        }
        return 1 + p.depth();
    }
}
