package xcheckscope;

enum CFault {
	Only(tag:String);
	// A declared variant whose name collides with the growth variant the
	// throw side would synthesize for CException.
	CExceptionFault(n:Int);
}

class CException extends haxe.Exception {
	public final fault:CFault;

	public function new(fault:CFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:CFault):String {
		return switch (f) {
			case Only(t): t;
			case CExceptionFault(n): "" + n;
		};
	}
}

class DeadCollProbe {
	// Unreferenced private static: never emitted.
	static function deadRethrow(v:CFault):Int {
		try {
			throw new CException(v);
		} catch (e:CException) {
			return 1;
		}
		return 0;
	}

	public static function liveFault(v:CFault):Int {
		return switch (v) {
			case Only(t): t.length;
			case CExceptionFault(n): n;
		};
	}

	public static function main():Void {}
}
