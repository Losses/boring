package boring;

/**
 * R1 regression sample (ClassInstanceLocalLet): a local bound to a
 * class instance the emitter proves never reassigned declares let,
 * even though the referenced object's fields mutate.
 **/
class ClassInstanceLocalLet {
	public var n:Int;

	public function new() {
		n = 3;
	}

	public static function bump():Int {
		var inst = new ClassInstanceLocalLet();
		inst.n = 5;
		return inst.n;
	}
}
