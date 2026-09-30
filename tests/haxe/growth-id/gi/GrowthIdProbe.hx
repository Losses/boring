package gi;

/**
	Counterexample fixture for t-munebyud-bxbr (TCN-109): the rethrow
	growth-variant REGISTRATION keyed the exception class's payload enum,
	while the LOOKUP (RustExpr.throwVariant) reads the error type active at
	the throw site — the enclosing try region's catch domain when the throw
	is absorbed, otherwise the containing function's Result error enum. This
	fixture exercises the "otherwise" arm:

	`mixed()` carries an unabsorbed `throw new A(...)`, so the propagation
	fixpoint settles its Result error enum to AFault; the rethrow
	`throw new E(e.fault)` sits at function top level — NOT inside any try
	region — so its throw site looks the growth table up under AFault.

	Pre-fix the variant `EFault` was registered on the enum `EFault`, an
	identity the AFault throw site never consults; the emitter fell back to
	`AFault::EFault(...)` — a constructor AFault never declared — and cargo
	failed with E0599 after a SILENT generation pass (gen rc=0). Post-fix the
	registration follows the lookup's own identity predicate
	(RustEmissionState.throwGrowthKey) and lands on AFault, which then grows
	the wrapping variant (RustDecl declared-enum emission).

	`sameDomain()` is the control: its rethrow sits inside a region whose
	catch domain is E's own payload enum, so both identities coincide and it
	must compile before AND after the fix.

	Declaration order here: A domain first, E second. `girev/` mirrors it.
**/
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

class GrowthIdProbe {
	// The unabsorbed A throw fixes this function's Result error enum to
	// AFault; the unabsorbed throw of E over a value-shaped (non
	// payload-constructor) argument must then land a variant on AFault.
	public static function mixed(f:EFault):Int {
		if (arm()) {
			throw new A(AFault.Alpha("a"));
		}
		throw new E(f);
	}

	public static function arm():Bool {
		return false;
	}

	// Control: rethrow inside a region catching E's own payload domain —
	// registration and lookup identities coincide here.
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

	// No main(): the load-bearing reading is cargo build on the generated
	// library (same as the PIT-281 counterexample); no harness is committed.
}
