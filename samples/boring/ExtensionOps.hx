package boring;

enum ExtensionMode {
	Cold;
	Hot;
}

/** Native extension declarations backed by plain Haxe static calls. */
class ExtensionOps {
	@:extension
	public static function modeLabel(mode:ExtensionMode, suffix:String):String {
		return mode == ExtensionMode.Hot ? "hot" + suffix : "cold" + suffix;
	}

	@:extension
	public static function stringLabel(value:String, prefix:String):String {
		return prefix + value;
	}

	@:extension
	static function privateModeLabel(mode:ExtensionMode):String {
		if(mode == ExtensionMode.Hot) return "private-hot";
		return "private-cold";
	}

	@:extension
	public static function modeWithPrivate(mode:ExtensionMode):String {
		return privateModeLabel(mode);
	}
}
