package xcheckscope;

/** Boundary fixture: two payload exception classes declared in the SAME module.
    The emitter keys its exception-payload map by class module, so this shape
    probes whether the throw-side registration picks the payload enum of the
    class actually thrown. */
enum F2 {
	Two(t:String);
}

class E2 extends haxe.Exception {
	public final fault:F2;

	public function new(fault:F2) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:F2):String {
		return switch (f) {
			case Two(t): t;
		};
	}
}

enum F1 {
	One(t:String);
}

class E1 extends haxe.Exception {
	public final fault:F1;

	public function new(fault:F1) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:F1):String {
		return switch (f) {
			case One(t): t;
		};
	}
}

class TwoProbe {
	public static function throwE1(t:String):Int {
		throw new E1(F1.One(t));
	}

	public static function throwE2(t:String):Int {
		throw new E2(F2.Two(t));
	}

	// rethrow E1: needs variant on F1
	public static function rethrowE1():Int {
		var v = 0;
		try {
			throwE1("a");
		} catch (e:E1) {
			final h = try {
				throw new E1(e.fault);
				99;
			} catch (e2:E1) {
				5;
			}
			v = h;
		}
		return v;
	}

	// rethrow E2: needs variant on F2
	public static function rethrowE2():Int {
		var v = 0;
		try {
			throwE2("b");
		} catch (e:E2) {
			final h = try {
				throw new E2(e.fault);
				99;
			} catch (e2:E2) {
				6;
			}
			v = h;
		}
		return v;
	}

	public static function main():Void {}
}
