package boring;

class StringConvOps {
	public static function hexZero():String return StringTools.hex(0);

	public static function hexTen():String return StringTools.hex(10);

	public static function hexByte():String return StringTools.hex(255);

	public static function hexCjk():String return StringTools.hex(40959);

	public static function hexDigitsZero():String return StringTools.hex(10, 0);

	public static function hexPadded():String return StringTools.hex(10, 4);

	public static function hexWiderThanDigits():String return StringTools.hex(40959, 2);

	public static function hexDynamic(value:Int, digits:Int):String return StringTools.hex(value, digits);

	public static function hexLowercase():String return "U+" + StringTools.hex(40959, 0).toLowerCase();

	public static function lowerAscii():String return "TiQian".toLowerCase();

	public static function upperAscii():String return "tiqian".toUpperCase();

	public static function lowerLanguageTag():String return "ZH-CN".toLowerCase();

	public static function upperLanguageTag():String return "zh-cn".toUpperCase();

	public static function lowerCjk():String return "提椠排版".toLowerCase();

	public static function upperCjk():String return "提椠排版".toUpperCase();

	public static function lowerDynamic(value:String):String return value.toLowerCase();

	public static function upperDynamic(value:String):String return value.toUpperCase();
}
