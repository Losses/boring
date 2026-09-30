package dcpe;

/**
    Source-level negative control: the same side-effecting subject is written at
    two source positions, so any faithful lowering evaluates `nextKind()` twice
    and `callCount` ends at 2 after one call to `doubleOnce()`.

    This control exists to show that the assertion of the positive probe (read
    `callCount` after one call, expect 1) is able to observe the value 2 through
    the very same generation, compilation and invocation path. It is a control
    on the *assertion*, not a claim about the promoted shape: the promoted
    shape itself is mutated inside the generated tree by the runner (see
    `run.sh`, `mutate`), which is the control that covers duplicate rendering of
    a single switch's scrutinee.
**/
class DoubleEvalControl {
	public static var callCount:Int = 0;

	public static function nextKind():Kind {
		callCount = callCount + 1;
		return Kind.B(21);
	}

	public static function reset():Void {
		callCount = 0;
	}

	public static function doubleOnce():Int {
		var acc:Int = 0;
		switch (nextKind()) {
			case Kind.A:
				acc = 1;
			case Kind.B(value):
				acc = value;
			case Kind.C:
				acc = 3;
		}
		switch (nextKind()) {
			case Kind.A:
				acc = acc + 1;
			case Kind.B(value):
				acc = acc + value;
			case Kind.C:
				acc = acc + 3;
		}
		return acc;
	}

	public static function main():Void {}
}
