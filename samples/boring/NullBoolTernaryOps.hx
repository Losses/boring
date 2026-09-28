package boring;

/**
    A Null<Bool> local read from a record field, narrowed by an
    `if (x != null)` guard, then used inside a ternary in the guarded
    branch. The branch binding already holds the inner bool, so the Rust
    emission must not re-apply the Option forcing read on it.
*/
class NullBoolTernaryOps {
    public static function flagText(style:NullBoolStyle):String {
        final italic = style.italic;
        if (italic != null) {
            return italic ? "true" : "false";
        }
        return "absent";
    }

    public static function flagBit(style:NullBoolStyle):Int {
        final italic = style.italic;
        if (italic != null) {
            return italic ? 1 : 0;
        }
        return -1;
    }
}
