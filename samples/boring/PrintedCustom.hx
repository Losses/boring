package boring;

/**
 * A marked record with an explicit printed member. The explicit text wins
 * over record member synthesis on every target.
 */
@:dataClass
class PrintedCustom {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function toString():String {
		return "custom=" + value;
	}
}
