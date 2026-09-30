package xcheckscope;

/** Boundary fixture: a generic exception class rethrows a value. The gate has
    no type-parameter check, so this probes what the emission does when the
    exception class carries a type parameter. */
enum GFault {
	GOne(tag:String);
}

class GEx<T> extends haxe.Exception {
	public final fault:GFault;

	public function new(fault:GFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:GFault):String {
		return switch (f) {
			case GOne(t): t;
		};
	}
}

class GenProbe {
	public static function failG(tag:String):Int {
		throw new GEx<Int>(GFault.GOne(tag));
	}

	public static function rethrowG():Int {
		var v = 0;
		try {
			failG("g");
		} catch (e:GEx<Dynamic>) {
			final h = try {
				throw new GEx<Int>(e.fault);
				99;
			} catch (e2:GEx<Dynamic>) {
				8;
			}
			v = h;
		}
		return v;
	}

	public static function main():Void {}
}
