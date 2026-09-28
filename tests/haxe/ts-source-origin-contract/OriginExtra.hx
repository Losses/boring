package;

class OriginExtra {
	public static function main():Void {
		var value = 7;
		value = value + 1;
		std.Fs.exists("unused-path");
	}
}
