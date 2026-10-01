package cma;

/**
	Cross-module same-name growth fixture (t-muoqr42y-5bu3): module cma and
	module cmb each declare an enum named `EFault` and a class named `B`
	(payload enum `BFault`). Both classes are rethrown by value from a
	function whose Result error enum is the LOCAL `EFault`, so both throws
	register a growth variant named `BFault` on the growth key `EFault`.

	The growth table is keyed by the BARE enum name, so the two modules share
	one bucket: the first registration's callee path (`crate::cma::cross_a::B`
	or `crate::cmb::cross_b::B`) wins, the second is dropped by the
	calleeName dedup. The loser's enum then emits a variant carrying the
	winner's payload type while the loser's throw site constructs the loser's
	own `B` — the shape this fixture measures.

	Declaration order in this module matches cmb/CrossB.hx exactly; only the
	Haxe package differs.
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

class CrossA {
	// The payload-constructor throw of X settles this function's Result error
	// enum to the local EFault; the value-shaped throw of B then registers a
	// `BFault` growth variant on `EFault` (ThrowFaultVariantGrowth).
	public static function run(f:BFault):Int {
		if (arm()) {
			throw new X(EFault.Alpha("a"));
		}
		throw new B(f);
	}

	public static function arm():Bool {
		return false;
	}
}
