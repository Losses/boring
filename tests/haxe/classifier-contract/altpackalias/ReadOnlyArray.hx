package altpackalias;

/**
 * A typedef declaration that carries the name ReadOnlyArray in another
 * package. Its raw form is TType with declaration name ReadOnlyArray, so a
 * name check accepts it while an identity check rejects it. This is the
 * form that separates a declaration-name match from a module match.
 */
typedef ReadOnlyArray<T> = Array<T>;
