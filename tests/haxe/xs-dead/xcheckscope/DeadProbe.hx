package xcheckscope;

enum DFault {
	Only(tag:String);
}

class DException extends haxe.Exception {
	public final fault:DFault;

	public function new(fault:DFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:DFault):String {
		return switch (f) {
			case Only(t): t;
		};
	}
}

class DeadProbe {
	// Unreferenced private static: the emitter prunes these, so the rethrow
	// below is never emitted.
	static function deadRethrow(v:DFault):Int {
		try {
			throw new DException(v);
		} catch (e:DException) {
			return 1;
		}
		return 0;
	}

	public static function liveFault(v:DFault):Int {
		return switch (v) {
			case Only(t): t.length;
		};
	}

	public static function main():Void {}
}
