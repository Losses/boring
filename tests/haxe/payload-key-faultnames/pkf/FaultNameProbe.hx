package pkf;

/**
	Rename control for the second root cause (PIT-281 verification 4): same
	module/two-exception shape as pk/PayloadKeyProbe.hx, but the payload
	enums are named *PayloadFault so error-enum names carry the Fault suffix.
	Reconstructed from the hash-anchored generated tree in
	dc-warn/out/rust-payload-key/evidence/control-faultnames/ (the Haxe source
	was never committed; this is the driver for gen/rust-faultnames.hxml).
**/
enum E2PayloadFault {
	Two(tag:String);
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

enum E1PayloadFault {
	One(tag:String);
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

class FaultNameProbe {
	public static function throwE1(tag:String):Int {
		throw new E1(E1PayloadFault.One(tag));
	}

	public static function throwE2(tag:String):Int {
		throw new E2(E2PayloadFault.Two(tag));
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
				7;
			}
			v = h;
		}
		return v;
	}
}