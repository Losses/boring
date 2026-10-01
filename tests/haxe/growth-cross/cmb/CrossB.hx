package cmb;

/**
	Cross-module same-name growth fixture (t-muoqr42y-5bu3), mirror of
	cma/CrossA.hx with an independent declaration of the SAME bare names:
	`EFault`, `BFault`, `X`, `B`. Different Haxe package -> different Rust
	module, so the emitted Rust types are `crate::cmb::cross_b::EFault` and
	`crate::cmb::cross_b::B` even though the growth table cannot tell them
	apart from cma's same-named types.
**/
enum EFault {
	Alpha(tag:String);
}

class X extends haxe.Exception {
	public final fault:EFault;

	public function new(fault:EFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:EFault):String {
		return switch (f) {
			case Alpha(t): t;
		};
	}
}

enum BFault {
	Bad(tag:String);
}

class B extends haxe.Exception {
	public final fault:BFault;

	public function new(fault:BFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:BFault):String {
		return switch (f) {
			case Bad(t): t;
		};
	}
}

class CrossB {
	public static function run(f:BFault):Int {
		if (arm()) {
			throw new X(EFault.Alpha("b"));
		}
		throw new B(f);
	}

	public static function arm():Bool {
		return false;
	}
}
