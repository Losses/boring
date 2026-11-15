package probe;

/** Class root that types the mutually recursive typedef pair. */
class MutualRoot {
    public static function count(node:MutualA):Int {
        if (node == null) {
            return 0;
        }
        return node.peers.length;
    }
}
