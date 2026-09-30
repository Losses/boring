package classemit;

/**
	Discriminating fixture for the class-level struct emission of a
	thrown-value exception class (ThrowFaultVariantGrowth).

	Shape: ONE payload exception class in its own module, rethrown by value
	(`throw new E1(e.fault)`), with a payload enum whose name ends in `Fault`
	so the throw-site wrap path (RustExpr.throwVariant) is active. The
	rethrow therefore renders `E1Fault::E1Fault(Box::new(E1::new(e)))`: the
	generated Rust names both the growth variant and the exception class
	struct, so a missing `pub struct E1` is a hard rustc error (E0433) and
	not merely an absent declaration.

	`plainThrow()` is the constructor-shaped control: it lowers to the
	payload directly and must not need the exception struct.
**/
enum E1Fault {
	Only(tag:String);
}

class E1 extends haxe.Exception {
	public final fault:E1Fault;

	public function new(fault:E1Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(_fault:E1Fault):String {
		return switch (_fault) {
			case Only(tag): tag;
		};
	}
}

class ClassEmitProbe {
	public static function mustThrow(tag:String):Void {
		throw new E1(E1Fault.Only(tag));
	}

	// Rethrow-of-value: the only shape that names the exception class.
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
