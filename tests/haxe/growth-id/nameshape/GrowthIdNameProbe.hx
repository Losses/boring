package nameshape;

/**
	Sibling-shape fixture for t-munebyud-bxbr (the enumDeclaresVariant half):
	the payload enum EFault declares a construct whose RAW Haxe name is
	`e_fault` but which EMITS as `EFault` (RustDecl.hx renders every
	constructor through RustImports.toUpperCamelCase) — exactly the name the
	rethrow growth variant for class E takes.

	Pre-fix the dedup compared raw names (`e_fault` != `EFault`), missed the
	collision, registered the growth variant, and the emitted enum carried
	two `EFault` constructors -> cargo E0428 (duplicate definition).

	Post-fix the dedup compares the emitted name and suppresses the
	registration, so E0428 disappears. The residual fallback in
	RustExpr.throwVariant still names `EFault` for the rethrow with mismatched
	arity — that is a separately-recorded defect (see REPORT), deliberately
	NOT fixed in this row.
**/
enum EFault {
	Bad(tag:String);
	E_fault(tag:String);
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
			case E_fault(t): "ef " + t;
		};
	}
}

class GrowthIdNameProbe {
	public static function rethrowOnly():Int {
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
