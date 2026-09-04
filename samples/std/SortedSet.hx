package std;

/**
 * Standard library extern for immutable sorted set (docs/specs/stdlib/07-sorted-keyed-tables.md).
 * References route through each target's import table into the runtime package.
 */
extern class SortedSet<K> {
    public function has(key:K):Bool;
    public function size():Int;
    public function at(index:Int):K;
    public static function builder<K>():SortedSetBuilder<K>;
}

extern class SortedSetBuilder<K> {
    public function put(key:K):Void;
    public function build():SortedSet<K>;
}
