package xcheckscope;

/** Boundary fixture: plain enum / constructor-shaped throw / rethrow-of-value /
    message-only exception, all in separate functions so a failure in one shape
    cannot mask another. */
enum Plain {
	Alpha;
	Beta(v:Int);
}

enum PFault {
	Only(tag:String);
	Pair(a:String, b:String);
}

class PEx extends haxe.Exception {
	public final fault:PFault;

	public function new(fault:PFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:PFault):String {
		return switch (f) {
			case Only(tag): tag;
			case Pair(a, b): a + b;
		};
	}
}

class ScopeProbe {
	public static function plainSwitch(p:Plain):Int {
		return switch (p) {
			case Alpha: 0;
			case Beta(v): v;
		};
	}

	public static function mustThrowP(tag:String):Void {
		throw new PEx(PFault.Only(tag));
	}

	// constructor-shaped throw with a single-arg enum constructor
	public static function ctorSingle():Int {
		var v = 0;
		try {
			throw new PEx(PFault.Only("s"));
		} catch (e:PEx) {
			v = 1;
		}
		return v;
	}

	// constructor-shaped throw with a multi-arg enum constructor
	public static function ctorPair():Int {
		var v = 0;
		try {
			throw new PEx(PFault.Pair("a", "b"));
		} catch (e:PEx) {
			v = 2;
		}
		return v;
	}

	// rethrow of a caught exception value: the shape the patch targets
	public static function rethrowValue():Int {
		var v = 0;
		try {
			mustThrowP("r");
		} catch (e:PEx) {
			final h = try {
				throw new PEx(e.fault);
				99;
			} catch (e2:PEx) {
				3;
			}
			v = h;
		}
		return v;
	}

	public static function main():Void {}
}
