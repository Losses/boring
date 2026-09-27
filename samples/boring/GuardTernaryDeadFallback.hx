package boring;

/**
 * R1 regression sample (GuardTernaryArgNonNull): an argument that is a
 * null-guard ternary - the taken branch unwraps, the default branch is
 * a typed non-null value - must not receive the call-site default
 * fallback, which can never execute and warns as dead.
 **/
class GuardTernaryDeadFallback {
	public static function take(s:String = "d"):String {
		return s;
	}

	public static function go(r:Null<String>):String {
		return take(r != null ? r : "x");
	}
}
