package twoemitrevscope;

/**
	Reverse-declaration-order control for xt-twoexc-emit.

	Same shape (two payload exception classes sharing ONE Haxe module, only E1
	rethrown by value so only E1 needs `pub struct E1`), but the declaration
	order is flipped: E1 is declared FIRST here, E2 LAST. The module-keyed
	payload bookkeeping therefore keeps E2's payload name and drops E1's,
	while E1 is still the class the generated tree depends on.

	A correct fix must compile BOTH declaration orders; a scan-order dependent
	"fix" compiles exactly one of them.
**/
enum E1Fault {
	One(tag:String);
}

class E1 extends haxe.Exception {
	public final fault:E1Fault;

	public function new(fault:E1Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(_fault:E1Fault):String {
		return switch (_fault) {
			case One(tag): tag;
		};
	}
}

enum E2Fault {
	Two(tag:String);
}

class E2 extends haxe.Exception {
	public final fault:E2Fault;

	public function new(fault:E2Fault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(_fault:E2Fault):String {
		return switch (_fault) {
			case Two(tag): tag;
		};
	}
}

class TwoEmitProbeRev {
	// Constructor-shaped throw of E2: lowers to E2Fault directly, no struct.
	public static function throwE2(tag:String):Void {
		throw new E2(E2Fault.Two(tag));
	}

	public static function mustThrowE1(tag:String):Void {
		throw new E1(E1Fault.One(tag));
	}

	// Rethrow-of-value of E1: the reference that needs `pub struct E1`.
	public static function rethrowE1():Int {
		var v = 0;
		try {
			mustThrowE1("rethrow");
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

	public static function main():Void {}
}
