package boring;

class Frame {
	public final label:String;
	public function new(label:String) {
		this.label = label;
	}
}

enum FrameMode {
	Plain;
	Weighted(weight:Float);
}

class FrameBase {
	public static final factor:Float = 1.5;
}

class BuiltInFrame {
	public static final frame:Frame = new Frame("cross-class");
}

class FramePolicy {
	public final label:String;
	public final mode:FrameMode;
	public final values:Array<String>;
	public function new(label:String, mode:FrameMode, values:Array<String>) {
		this.label = label;
		this.mode = mode;
		this.values = values;
	}

	public static final weighted:FramePolicy = new FramePolicy("weighted", FrameMode.Weighted(FrameBase.factor), ["a", "b"]);
	public static final plain:FramePolicy = new FramePolicy("plain", FrameMode.Plain, []);
	public static final imported:FramePolicy = new FramePolicy("imported", FrameMode.Plain, ["cross-class"]);
	public static final generated:FramePolicy = new FramePolicy("generated", FrameMode.Plain, []);
}

class ConstructedStateOps {
	public static function labels():String {
		return FramePolicy.weighted.label + "," + FramePolicy.plain.label + "," + FramePolicy.imported.label + "," + FramePolicy.generated.label;
	}
	public static function weight():Float {
		return FrameBase.factor;
	}
	public static function firstLengths():String {
		return FramePolicy.weighted.values.length + "," + FramePolicy.plain.values.length;
	}
	public static function crossClassText():String return BuiltInFrame.frame.label;
	public static function generatedLabel():String return FramePolicy.generated.label;
}
