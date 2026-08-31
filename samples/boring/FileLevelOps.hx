package boring;

/** File-scope functions extracted from a marked static namespace. */
class FileLevelOps {
	@:topLevel
	public static function publicValue(value:Int):Int {
		return value + 10;
	}

	@:topLevel
	static function privateValue(value:Int):Int {
		return value + 20;
	}

	@:topLevel
	public static function publicWithPrivate(value:Int):Int {
		return privateValue(value);
	}
}
