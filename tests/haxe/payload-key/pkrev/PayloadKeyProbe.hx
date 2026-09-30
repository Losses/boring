package pkrev;

/**
	Counterexample fixture for PIT-281 (task t-mune0a1j-vmt1): ONE Haxe module
	carrying TWO payload exception classes. The scanner records the payload
	enum bookkeeping keyed by the payload enum's MODULE, so both classes write
	the same key and the later scan wins ("last-scanned survives"). Both
	classes are rethrown by value, so the generated tree needs BOTH
	`pub struct E1` and `pub struct E2` plus growth variants on BOTH fault
	enums; with the module key the first class loses its registration and the
	generated Rust references a type that was never emitted (cargo E0433).

	Declaration order here: E2 first, E1 last (E1 wins the module key).
	The payload-key-rev fixture swaps the declaration order to prove the
	mirror signature ("whoever is scanned last is usable") is gone after the
	fix.
**/
enum E2Fault {
	Two(tag:String);
}

class E2 extends haxe.Exception {
	public final fault:E2Fault;

	public function new(fault:E2Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:E2Fault):String {
		return switch (f) {
			case Two(t): t;
		};
	}
}

enum E1Fault {
	One(tag:String);
}

class E1 extends haxe.Exception {
	public final fault:E1Fault;

	public function new(fault:E1Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:E1Fault):String {
		return switch (f) {
			case One(t): t;
		};
	}
}

class PayloadKeyProbe {
	public static function throwE1(tag:String):Int {
		throw new E1(E1Fault.One(tag));
	}

	public static function throwE2(tag:String):Int {
		throw new E2(E2Fault.Two(tag));
	}

	// Rethrow of a caught E1 value: forces the E1 class struct and an
	// E1Fault growth variant (ThrowFaultVariantGrowth).
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

	// Rethrow of a caught E2 value: the mirrored requirement for E2.
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

	// No main(): the native harness calls the static entries directly, the
	// same shape the try-tail fixture uses.
}
