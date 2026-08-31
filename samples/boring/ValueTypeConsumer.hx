package boring;

import boring.ValueTypeOps.FontFaceId;
import boring.ValueTypeOps.Ic;

/** Cross-module uses of both marked wrapper shapes. */
class ValueTypeConsumer {
	public static function arithmetic():Float {
		final first:Ic = new Ic(2.0);
		final total = first + Ic.ZERO;
		return total.toPx(3.0);
	}

	public static function equalRepresentations():Bool {
		return new Ic(2.0) == new Ic(2.0);
	}

	public static function staticValue():Float {
		return Ic.ZERO.toPx(5.0);
	}

	public static function blankRejected():Bool {
		var rejected = false;
		try {
			new FontFaceId(" ");
		} catch (error:ValueException) {
			rejected = true;
		}
		return rejected;
	}

	public static function renderedId():String {
		final id:FontFaceId = new FontFaceId("face");
		return id.toString();
	}
}
