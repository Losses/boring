package dcpe;

/**
    Positive probe: a statement-position (promoted) enum switch whose subject
    is a side-effecting non-local call.

    `nextKind()` increments the static counter `callCount` on every execution
    and always returns the same construct, `Kind.B(21)`. The subject being
    side-effecting is what makes the "single evaluation" claim measurable: if a
    target emits the scrutinee expression in more than one place, `callCount`
    ends at 2 or more after one call to `promotedOnce()`.

    The switch sits in statement position, so the Haxe 4.3.7 typer promotes the
    non-local subject into a synthetic local exactly as it does for the field
    subject of the dc-enum-switch-gen fixture; the promoted shape is therefore
    the shape every target accepts, and the only open question was whether the
    *runtime* evaluates the subject once.

    `nextKind()` returns one constant construct on purpose. A subject whose
    value depended on the call ordinal would let a duplicate evaluation change
    control flow, which would confound the counter assertion with a value
    mismatch.
**/
class EvalProbe {
	public static var callCount:Int = 0;

	public static function nextKind():Kind {
		callCount = callCount + 1;
		return Kind.B(21);
	}

	public static function reset():Void {
		callCount = 0;
	}

	public static function promotedOnce():Int {
		var acc:Int = 0;
		switch (nextKind()) {
			case Kind.A:
				acc = 1;
			case Kind.B(value):
				acc = value;
			case Kind.C:
				acc = 3;
		}
		return acc;
	}

	public static function main():Void {}
}
