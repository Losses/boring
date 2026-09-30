package trytailmin;

/**
	Minimal reproduction fixture for the Rust ThrowFaultVariantGrowth fix
	(task t-mun5d97u-c4md): a rethrow of a caught exception value
	(`throw new MinException(e.fault)`) must grow its payload fault enum
	with the wrapping variant the throw references, and the exception class
	must emit beside the enum. plainThrow() covers the constructor-shaped
	throw that lowers to the payload directly and must stay byte-identical.
**/
enum MinFault {
	Only(tag:String);
}

class MinException extends haxe.Exception {
	public final fault:MinFault;

	public function new(fault:MinFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(_fault:MinFault):String {
		return switch (_fault) {
			case Only(tag): tag;
		};
	}
}

class MinOracle {
	public static function mustThrow(tag:String):Void {
		throw new MinException(MinFault.Only(tag));
	}

	// Rethrow-of-value: the shape that names the growth variant.
	public static function rethrowHandler():Int {
		var v = 0;
		try {
			mustThrow("rethrow");
		} catch (e:MinException) {
			final h = try {
				throw new MinException(e.fault);
				99;
			} catch (e2:MinException) {
				3;
			}
			v = h;
		}
		return v;
	}

	// Constructor-shaped throw: lowers to the payload directly, no variant.
	public static function plainThrow():Int {
		return try {
			mustThrow("plain");
			99;
		} catch (e:MinException) {
			1;
		}
	}
}
