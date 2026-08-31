package boring;

class ToStringOps {
	public static function makeLabel(text:String, width:Int):PlainLabel {
		return new PlainLabel(text, width);
	}

	public static function describe(label:PlainLabel):String {
		return label.toString();
	}
}
