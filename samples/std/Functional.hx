package std;

/**
 * Standard static extensions for functional idioms (docs/specs/features/21-functional-idiom-expansion.md).
 * In Haxe stage-1 JS output, calls bind to __functional_shim installed by the runner.
 * The compiler expands accepted collection pipeline calls to loops before target emission.
 */
@:native("__functional_shim")
extern class Functional {
	public static function forEach<T>(arr:Array<T>, fn:(item:T) -> Void):Void;
	public static function associate<T, K, V>(arr:Array<T>, fn:(item:T) -> {key:K, value:V}):std.SortedMap<K, V>;
	public static function sortedBy<T, K>(arr:Array<T>, keyFn:(item:T) -> K):Array<T>;
}
