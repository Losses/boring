package boring;

@:sealed
interface DrawKind {}

class NoneDrawKind implements DrawKind {
	public static final instance:NoneDrawKind = new NoneDrawKind();

	private function new() {}
}

@:dataClass
class StripeDrawKind implements DrawKind {
	public final strokeWidth:Float;
	public final gapLength:Float;

	public function new(strokeWidth:Float, gapLength:Float) {
		this.strokeWidth = strokeWidth;
		this.gapLength = gapLength;
	}
}

@:dataClass
class DotDrawKind implements DrawKind {
	public final dotDiameter:Float;
	public final gapLength:Float;

	public function new(dotDiameter:Float, gapLength:Float) {
		this.dotDiameter = dotDiameter;
		this.gapLength = gapLength;
	}
}

class SealedVariantOps {
	public static function labelOf(kind:DrawKind):String {
		if (Std.isOfType(kind, NoneDrawKind)) {
			return "none";
		}
		if (Std.isOfType(kind, StripeDrawKind)) {
			return "stripe";
		}
		if (Std.isOfType(kind, DotDrawKind)) {
			return "dot";
		}
		return "unknown";
	}

	public static function noneLabel():String {
		return Std.string(NoneDrawKind.instance);
	}
}
