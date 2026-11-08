package probe;

class StaticNoInitProbe {
	public static var table:Array<Array<Int>>;

	public static function read():Array<Array<Int>> {
		return table;
	}

	static function main():Void {}
}
