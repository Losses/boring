package boring;

/**
 * R1 regression sample (guardedNonNullTernary elvis wrap): a read the
 * emitter proves non-null through the receiver's own extraction - a
 * declared field or a getter property rendered as a declared property -
 * must stay on the non-null path: no second extraction and no wrapping
 * elvis at the call or fold boundary, which would warn as redundant.
 **/
class GuardedNonNullTernaryElvis {
	public var size(get, never):Int;

	function get_size():Int {
		return 2;
	}

	public static function read(r:Null<GuardedNonNullTernaryElvis>):Int {
		return r.size;
	}

	public static function store(v:Int = -1):Int {
		return v;
	}

	public static function pick(flag:Bool, r:Null<GuardedNonNullTernaryElvis>):Int {
		return store(flag ? r.size : r.size);
	}
}
