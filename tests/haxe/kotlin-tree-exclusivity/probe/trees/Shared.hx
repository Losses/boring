package trees;

/** One type whose unit changes between the two runs of the fixture: test code
    alone references it in the first run, and a shipping-tree module references
    it in the second. */
class Shared {
    public final label:String;

    public function new(label:String) {
        this.label = label;
    }

    public function describe():String {
        return "shared:" + label;
    }
}
