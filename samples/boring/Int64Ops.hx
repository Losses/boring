package boring;

import haxe.Int64;

/** Fixed-width Int64 operations shared by the target capability tests. */
class Int64Ops {
	public static function carry():Int64 {
		return Int64.make(0, -1) + Int64.ofInt(1);
	}

	public static function rotate(value:Int64, distance:Int):Int64 {
		return (value >>> distance) | (value << (64 - distance));
	}

	public static function bitMix(value:Int64):Int64 {
		return (value ^ Int64.make(0xAAAAAAAA, 0x55555555)) | (value & Int64.make(0x55555555, 0xAAAAAAAA));
	}

	public static function high(value:Int64):Int {
		return Int64.getHigh(value);
	}

	public static function below(a:Int64, b:Int64):Bool {
		return a < b;
	}

	public static function atOrBelow(a:Int64, b:Int64):Bool {
		return a <= b;
	}
}
