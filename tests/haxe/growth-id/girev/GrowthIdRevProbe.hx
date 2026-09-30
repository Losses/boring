package girev;

/**
	Order-swap mirror of gi/GrowthIdProbe.hx (t-munebyud-bxbr): the E domain
	is declared FIRST here, A second. The registration/lookup identity
	mismatch is architectural (which enum each side keys), not scan-order
	sensitive, so both declaration orders must fail before the fix and pass
	after it.
**/
enum EFault {
	Bad(tag:String);
}

class E extends haxe.Exception {
	public final fault:EFault;

	public function new(fault:EFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:EFault):String {
		return switch (f) {
			case Bad(t): t;
		};
	}
}

enum AFault {
	Alpha(tag:String);
}

class A extends haxe.Exception {
	public final fault:AFault;

	public function new(fault:AFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:AFault):String {
		return switch (f) {
			case Alpha(t): t;
		};
	}
}

class GrowthIdRevProbe {
	public static function mixed(f:EFault):Int {
		if (arm()) {
			throw new A(AFault.Alpha("a"));
		}
		throw new E(f);
	}

	public static function arm():Bool {
		return false;
	}

	public static function sameDomain():Int {
		var v = 0;
		try {
			throw new E(EFault.Bad("b"));
		} catch (e:E) {
			final h = try {
				throw new E(e.fault);
				99;
			} catch (e2:E) {
				5;
			}
			v = h;
		}
		return v;
	}
}
