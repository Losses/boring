package std;

/**
 * Read-only array type per docs/specs/features/18-immutability.md.
 * Forwards length and indexed reads; no mutation member exists on the
 * abstract, so a mutation attempt fails Haxe compilation. The abstract
 * erases after typing and adds no runtime cost on any target.
 */
@:forward(length)
abstract ReadOnlyArray<T>(Array<T>) from Array<T> {
	public extern function iterator():Iterator<T>;

	@:arrayAccess inline function get(index:Int):T {
		return this[index];
	}
}
