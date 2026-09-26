package boring;

// Minimal null-shape samples for the dart backend (SOP5).
// Shape A: pushing null into an Array<Null<T>> must not emit a non-null
// assertion on the pushed element in dart.
// Shape B: a closure whose return type is nullable must be allowed to
// return null without a non-null assertion in dart.
class DartNullPushOps {
	public static function pushNullIntoNullableArray():Null<Int> {
		final xs:Array<Null<Int>> = [];
		xs.push(1);
		xs.push(null);
		return xs[1];
	}

	public static function pushValueIntoNullableArray():Null<Int> {
		final xs:Array<Null<Int>> = [];
		xs.push(1);
		xs.push(2);
		return xs[1];
	}

	public static function nullableClosureReturnsNull():Null<Int> {
		final f:Void->Null<Int> = function():Null<Int> {
			return null;
		};
		return f();
	}

	public static function nullableClosureReturnsValue():Null<Int> {
		final f:Void->Null<Int> = function():Null<Int> {
			return 7;
		};
		return f();
	}
}
