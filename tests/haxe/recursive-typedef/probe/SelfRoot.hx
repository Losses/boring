package probe;

/** Class root that types the self-recursive typedef and its Leaf dependency. */
class SelfRoot {
    public static function count(rec:DiagRec):Int {
        if (rec == null) {
            return 0;
        }
        return rec.children.length + (rec.leaf == null ? 0 : 1);
    }
}
