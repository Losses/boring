package otherpkg;

enum ModFault {
	ModOne(tag:String);
}

class ModEx extends haxe.Exception {
	public final fault:ModFault;

	public function new(fault:ModFault) {
		this.fault = fault;
		super(describe(fault));
	}

	public static function describe(f:ModFault):String {
		return switch (f) {
			case ModOne(t): t;
		};
	}
}
