package boring;

class DeferredLocalsOps {
	public function new() {}

	public static function tierOf(value:Int):Int {
		var tier:Int;
		if (value > 2) {
			tier = 2;
		} else {
			tier = value;
		}
		return tier;
	}

	public static function nullableValue(value:Null<Int>):Int {
		var result:Int;
		if (value != null) {
			result = value;
		} else {
			result = 0;
		}
		return result;
	}

	public static function loopValue(count:Int):Int {
		var result:Int;
		result = 0;
		var i = 0;
		while (i < count) {
			result = i;
			i = i + 1;
		}
		return result;
	}
}
