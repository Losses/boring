package xcheckscope;

/** Boundary fixture: two payload exception classes declared in the SAME module.
    The emitter keys its exception-payload map by class module, so this shape
    probes whether the throw-side registration picks the payload enum of the
    class actually thrown. */
enum E1PayloadFault {
	One(t:String);
}

class E1 extends haxe.Exception {
	public final fault:E1PayloadFault;

	public function new(fault:E1PayloadFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:E1PayloadFault):String {
		return switch (f) {
			case One(t): t;
		};
	}
}

enum E2PayloadFault {
	Two(t:String);
}

class E2 extends haxe.Exception {
	public final fault:E2PayloadFault;

	public function new(fault:E2PayloadFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:E2PayloadFault):String {
		return switch (f) {
			case Two(t): t;
		};
	}
}

class TwoProbe {
	public static function throwE1(t:String):Int {
		throw new E1(E1PayloadFault.One(t));
	}

	public static function throwE2(t:String):Int {
		throw new E2(E2PayloadFault.Two(t));
	}

	// rethrow E1: needs variant on E1PayloadFault
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

	// rethrow E2: needs variant on E2PayloadFault
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
