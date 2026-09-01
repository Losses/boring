package boring;

class NumberParsingOps {
	public static function parseFloat(value:String):Float return Std.parseFloat(value);
	public static function parseInt(value:String):Null<Int> return Std.parseInt(value);
	public static function failedFloat(value:String):Bool return Math.isNaN(Std.parseFloat(value));
	public static function failedInt(value:String):Bool return Std.parseInt(value) == null;
}
