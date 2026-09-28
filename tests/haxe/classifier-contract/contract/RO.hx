package contract;

/**
 * A typedef alias of the project read-only array. Its declaration name is
 * RO, so a declaration-name check and an identity check answer it
 * differently. It stays in its own module so its module path names it.
 */
typedef RO<T> = std.ReadOnlyArray<T>;
