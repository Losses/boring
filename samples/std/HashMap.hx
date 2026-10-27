package std;

/**
 * Standard library extern for the mutable hash table
 * (docs/specs/stdlib/19-std-hashmap.md). References lower to each
 * target's native hash map; no runtime resident backs this type.
 */
extern class HashMap<K, V> {
    public function new():Void;
    public function get(key:K):Null<V>;
    public function exists(key:K):Bool;
    public function set(key:K, value:V):Void;
    public function remove(key:K):Bool;
    public function clear():Void;
}
