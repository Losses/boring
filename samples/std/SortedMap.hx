package std;

/**
 * Standard library extern for immutable sorted map (docs/specs/stdlib/07-sorted-keyed-tables.md).
 * References route through each target's import table into the runtime package.
 */
extern class SortedMap<K, V> {
	public function get(key:K):Null<V>;
	public function has(key:K):Bool;
	public function size():Int;
	public function keyAt(index:Int):K;
	public function valueAt(index:Int):V;
	public static function builder<K, V>():SortedMapBuilder<K, V>;
}

extern class SortedMapBuilder<K, V> {
	public function put(key:K, value:V):Void;
	public function build():SortedMap<K, V>;
}
