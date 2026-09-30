package xcheckscope;

import boring.ValueException;
import boring.ValueError;

/** Ordinary helper: throws the production payload exception. */
class ProdRethrowOps {
	public static function mustThrow():Void {
		throw new ValueException(ValueError.NegativeStart);
	}
}

/** Test module (@:test) that rethrows a production exception value. */
class ProdRethrowTests {
	@:test("rethrow of a production exception value from a test module")
	public static function rethrowProduction():Void {
		try {
			ProdRethrowOps.mustThrow();
		} catch (e:ValueException) {
			try {
				throw new ValueException(e.error);
			} catch (e2:ValueException) {}
		}
	}
}
