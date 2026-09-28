package;

class OriginSubject {
	@:topLevel
	public static function empty():Void {}

	public static function emit(value:String):Void {}

	public static function run():Void {
		emit("😀");
		emit("😀");
	}

	public static function main():Void {
		run();
		OriginSibling.run();
		OriginImported.run();
	}
}

class OriginSibling {
	public static function emit(value:String):Void {}

	public static function run():Void {
		emit("😀");
	}
}
