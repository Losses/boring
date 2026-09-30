package twoemitscope;

/**
	Two-exception-classes-in-one-module fixture for the class-level struct
	emission of a thrown-value exception class.

	Both payload enums live in the same Haxe module, so the emitter's
	payload-enum bookkeeping (Compiler.preScan, `state.payloadEnumNames` keyed
	by the payload enum's MODULE) keeps only the last class's payload name for
	that module key. E2 is declared FIRST and therefore loses the key; E1 is
	declared LAST and wins it. Only E1 needs the exception struct (it is
	rethrown by value); E2 is only constructed at a throw site, which lowers
	to its payload directly. That makes `pub struct E1` the single class-level
	emission the generated tree depends on for compiling.
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

	public static function describe(_fault:E2Fault):String {
		return switch (_fault) {
			case Two(tag): tag;
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

	public static function describe(_fault:E1Fault):String {
		return switch (_fault) {
			case One(tag): tag;
		};
	}
}

class TwoEmitProbe {
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
