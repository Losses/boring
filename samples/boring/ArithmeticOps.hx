package boring;

import std.Arithmetic;
import std.IntRange;

class ArithmeticOps {
	public static function checkWithinInt(value:Int, low:Int, high:Int):Bool {
		return Arithmetic.within(value, low, high);
	}

	public static function checkWithinFloat(value:Float, low:Float, high:Float):Bool {
		return Arithmetic.within(value, low, high);
	}

	public static function clampLeastInt(value:Int, floor:Int):Int {
		return Arithmetic.coerceAtLeast(value, floor);
	}

	public static function clampLeastFloat(value:Float, floor:Float):Float {
		return Arithmetic.coerceAtLeast(value, floor);
	}

	public static function clampMostInt(value:Int, ceiling:Int):Int {
		return Arithmetic.coerceAtMost(value, ceiling);
	}

	public static function clampMostFloat(value:Float, ceiling:Float):Float {
		return Arithmetic.coerceAtMost(value, ceiling);
	}

	public static function clampInInt(value:Int, low:Int, high:Int):Int {
		return Arithmetic.coerceIn(value, low, high);
	}

	public static function clampInFloat(value:Float, low:Float, high:Float):Float {
		return Arithmetic.coerceIn(value, low, high);
	}

	public static function inRange(start:Int, end:Int, value:Int):Bool {
		final range:IntRange = { start: start, end: end };
		return range.contains(value);
	}
}
