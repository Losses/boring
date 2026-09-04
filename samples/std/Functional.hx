package std;

/**
 * Standard static extensions for functional idioms (docs/specs/features/21-functional-idiom-expansion.md).
 * In Haxe stage-1 JS output, calls bind to __functional_shim installed by the runner.
 * The compiler expands accepted collection pipeline calls to loops before target emission.
 */
@:native("__functional_shim")
extern class Functional {
    public static function forEach<T>(arr:Array<T>, fn:(item:T) -> Void):Void;
    public static function associate<T, K, V>(arr:Array<T>, fn:(item:T) -> {
        final key:K;
        final value:V;
    }):std.SortedMap<K, V>;
    public static function sortedBy<T, K>(arr:Array<T>, keyFn:(item:T) -> K):Array<T>;
    public static function any<T>(arr:Array<T>, fn:(item:T) -> Bool):Bool;
    public static function all<T>(arr:Array<T>, fn:(item:T) -> Bool):Bool;
    public static function firstOrNull<T>(arr:Array<T>, fn:(item:T) -> Bool):Null<T>;
    public static function sumOfInt<T>(arr:Array<T>, fn:(item:T) -> Int):Int;
    public static function sumOfFloat<T>(arr:Array<T>, fn:(item:T) -> Float):Float;
    public static function mapNotNull<T, R>(arr:Array<T>, fn:(item:T) -> Null<R>):Array<R>;
    public static function flatMap<T, R>(arr:Array<T>, fn:(item:T) -> R):Dynamic;
    public static function groupBy<T, K, V>(arr:Array<T>, fn:(item:T) -> {
        final key:K;
        final value:V;
    }):std.SortedMap<K, Array<V>>;
}
