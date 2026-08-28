// Host edges of runtime.TestCore in the stage-one harness: the
// assertion checks live in the compiled resident, these primitives read
// the runner state and render plain numbers. The collector copies this
// file beside TestMain and binds it as globalThis.std.TestPlatform.
class TestPlatform {
	/** The id of the running test; the runner sets and clears it. */
	public static var currentId:Null<String> = null;

	public static function raise(canonical:String):Void {
		throw new haxe.Exception(canonical);
	}

	public static function currentTestId():String {
		return currentId == null ? "" : currentId;
	}

	public static function intToString(v:Int):String {
		return "" + v;
	}

	public static function floatToString(v:Float):String {
		return "" + v;
	}
}
