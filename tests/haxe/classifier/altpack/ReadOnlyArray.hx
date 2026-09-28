package altpack;

/**
 * A user declaration that reuses the name ReadOnlyArray outside the std
 * package. It exists to expose the difference between a name check, a
 * package check, and a module identity check on the same abstract form.
 */
@:forward(length)
abstract ReadOnlyArray<T>(Array<T>) from Array<T> {
	public extern function iterator():Iterator<T>;

	@:arrayAccess inline function get(index:Int):T {
		return this[index];
	}
}
