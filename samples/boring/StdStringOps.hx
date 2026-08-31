package boring;

class StdStringOps {
	public static function concatString(value:String):String return "string=" + Std.string(value);
	public static function concatInt(value:Int):String return "int=" + Std.string(value);
	public static function concatFloat(value:Float):String return "float=" + Std.string(value);
	public static function concatBool(value:Bool):String return "bool=" + Std.string(value);

	public static function stringValue(value:String):String return Std.string(value);
	public static function intValue(value:Int):String return Std.string(value);
	public static function floatValue(value:Float):String return Std.string(value);
	public static function boolValue(value:Bool):String return Std.string(value);
}
