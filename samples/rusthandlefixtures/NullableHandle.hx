package rusthandlefixtures;

// nullable handle: a Null<plain-class> field and argument.
class Node {
    public var next:Null<Node>;
    public function new() {
        next = null;
    }
}

class NullableHandleOps {
    public static function link(head:Null<Node>):Int {
        return head == null ? 0 : 1;
    }
}
