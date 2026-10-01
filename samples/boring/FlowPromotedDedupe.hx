package boring;

/**
 * R1 regression sample (flow-promoted unwrap dedupe and scope): after a
 * null guard the unwrap happens once, and a promotion dies at its scope
 * boundary - at a branch merge the forced read must come back, inside a
 * closure the captured local is unwrapped afresh.
 **/
class FlowPromotedDedupe {
	public static function acrossStatements(r:Null<String>):Int {
		if (r == null)
			return -1;
		var n = r.length;
		return n + r.length;
	}

	public static function mergeLeak(flag:Bool, r:Null<String>):Int {
		if (flag) {
			if (r == null)
				return 0;
		}
		return r.length;
	}

	public static function acrossClosures(r:Null<String>):Int {
		if (r == null)
			return 0;
		var f = function():Int return r.length;
		return f();
	}
}
