package xsxm;

/** Neighbour-shape probe (reviewer-authored): two payload exception classes in
    ONE Haxe module whose payload enums live in TWO DIFFERENT modules.
    In this shape `payloadEnumNames` does not collide, but `exceptionPayloads`
    (keyed by the exception class's own module) still does. */
class E1 extends haxe.Exception {
	public final fault:Faults1.F1Fault;

	public function new(fault:Faults1.F1Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:Faults1.F1Fault):String {
		return switch (f) {
			case One(t): t;
		};
	}
}

class E2 extends haxe.Exception {
	public final fault:Faults2.F2Fault;

	public function new(fault:Faults2.F2Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:Faults2.F2Fault):String {
		return switch (f) {
			case Two(t): t;
		};
	}
}

class CrossProbe {
	public static function throwE1(t:String):Int {
		throw new E1(Faults1.F1Fault.One(t));
	}

	public static function throwE2(t:String):Int {
		throw new E2(Faults2.F2Fault.Two(t));
	}

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
