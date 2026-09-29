package cases;

enum Shade {
	Dim;
	Mid;
	Bright;
}

@:dataClass
class EnumKeyRecord {
	public final shade:Shade;
	public final weight:Int;

	public function new(shade:Shade, weight:Int) {
		this.shade = shade;
		this.weight = weight;
	}
}

class EnumAdmission {
	public static function main():Void {}
}
