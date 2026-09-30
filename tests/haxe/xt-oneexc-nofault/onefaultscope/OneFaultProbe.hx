package onefaultscope;

/**
	Orthogonality control for the SECOND root cause (RustExpr.throwVariant's
	`endsWith(errorTypeName, "Fault")` gate).

	Shape: ONE payload exception class, so the module-keyed payload
	bookkeeping has no collision at all and the class-level emit gate is
	reached (a `pub struct E1` is emitted). The payload enum is named `F1`
	and therefore does not end in `Fault`, so the throw-site wrap path returns
	the raw `E1::new(...)` and the rethrow region mismatches (E0308) even
	though no key collides.

	If this fixture fails while xt-classemit (same shape, payload named
	E1Fault) passes, the suffix gate is a root cause independent of the
	key collision and cannot be fixed by any keying change.
**/
enum F1 {
	One(tag:String);
}

class E1 extends haxe.Exception {
	public final fault:F1;

	public function new(fault:F1) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(_fault:F1):String {
		return switch (_fault) {
			case One(tag): tag;
		};
	}
}

class OneFaultProbe {
	public static function mustThrow(tag:String):Void {
		throw new E1(F1.One(tag));
	}

	// Rethrow-of-value: names the exception class; the enclosing region is
	// typed F1 (does not end in "Fault").
	public static function rethrowHandler():Int {
		var v = 0;
		try {
			mustThrow("rethrow");
		} catch (e:E1) {
			final h = try {
				throw new E1(e.fault);
				99;
			} catch (e2:E1) {
				3;
			}
			v = h;
		}
		return v;
	}

	public static function main():Void {}
}
