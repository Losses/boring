package xcheckscope;

/** Boundary fixture for the PRE-EXISTING growth channel: a callee whose fault
    domain differs from the caller's declared fault enum must merge through the
    callee-edge registration, not through the new throw-side one. */
enum AFault {
	AOne(tag:String);
}

class AEx extends haxe.Exception {
	public final fault:AFault;

	public function new(fault:AFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:AFault):String {
		return switch (f) {
			case AOne(t): t;
		};
	}
}

class AOps {
	public static function failA(tag:String):Int {
		throw new AEx(AFault.AOne(tag));
	}
}

enum BFault {
	BOne(tag:String);
}

class BEx extends haxe.Exception {
	public final fault:BFault;

	public function new(fault:BFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:BFault):String {
		return switch (f) {
			case BOne(t): t;
		};
	}
}

enum CFault {
	COne(tag:String);
}

class COps {
	public static function failC(tag:String):Int {
		return AOps.failA(tag) + 1;
	}
}

class GrowthProbe {
	// caller declares BFault (own throw) and also reaches AOps.failA
	public static function mergeAIntoB(tag:String):Int {
		if (tag == "") {
			throw new BEx(BFault.BOne(tag));
		}
		return AOps.failA(tag) + 1;
	}

	// callee-edge chain: COps has no own throw, only AOps.failA
	public static function chainC(tag:String):Int {
		return COps.failC(tag) + 2;
	}

	// two callee domains, no own throw
	public static function twoCallees(tag:String):Int {
		return AOps.failA(tag) + COps.failC(tag);
	}

	public static function main():Void {}
}
