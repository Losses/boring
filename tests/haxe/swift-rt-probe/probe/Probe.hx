package probe;

/**
	Exclusive minimal fixture (task t-mun5d99p-op76): one concrete
	exception caught only by its own concrete type. The compilation
	names no `haxe.Exception` type or constructor, so the only reference
	to the Swift runtime symbol `BoringException` in the emitted tree is
	the conformance of the exception class itself. The tree must therefore
	contain `Runtime.swift`.
**/
enum ProbeFault {
	Single(tag:String);
}

class ProbeException extends haxe.Exception {
	public final fault:ProbeFault;

	public function new(fault:ProbeFault) {
		this.fault = fault;
		super(ProbeException.describe(fault));
	}

	public static function describe(_fault:ProbeFault):String {
		return switch (_fault) {
			case Single(tag): tag;
		};
	}
}

class Probe {
	public static function boom(tag:String):Void {
		throw new ProbeException(ProbeFault.Single(tag));
	}

	public static function catchConcrete(tag:String):Int {
		return try {
			boom(tag);
			99;
		} catch (e:ProbeException) {
			1;
		}
	}
}
