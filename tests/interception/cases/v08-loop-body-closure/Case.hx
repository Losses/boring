// expect: V08 LoopBodyClosure
class Case {
	static function main():Void {
		final items = new Array<Int>();
		for (index in 0...items.length) {
			final double = function(value:Int):Int {
				return value * 2;
			};
			double(index);
		}
	}
}
