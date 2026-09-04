#if (macro || reflaxe_runtime)
import haxe.macro.Context;

/**
	Target precision of the Haxe Float type, shared by every
	reflaxe target (feature spec 23). The switch selects the generated
	representation of every Float in one compilation; the wire format is
	unaffected.

	- `float-precision=f64` (or the absent define): `f64`, `Double`,
	  `number` is the default representation.
	- `float-precision=f32`: `f32` on Rust and `Float` on Kotlin; the
	  TypeScript compiler rejects the compilation at startup because
	  `number` is binary64.
**/
class FloatPrecision {
	/** True when the compilation uses binary32. Errors on any value outside f64/f32. */
	public static function isF32(): Bool {
		final value = Context.definedValue("float-precision");
		if(value == null || value == "f64") {
			return false;
		}
		if(value == "f32") {
			return true;
		}
		Context.error("float-precision accepts f64 or f32", Context.currentPos());
		return false;
	}
}
#end
