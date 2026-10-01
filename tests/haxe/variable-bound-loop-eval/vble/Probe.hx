package vble;

class Probe {
	public static var localReads:Int = 0;
	public static var lengthReads:Int = 0;

	static function readLocal(bound:Int):Int {
		localReads++;
		return bound;
	}

	static function readLength(values:Array<Int>):Int {
		lengthReads++;
		return values.length;
	}

	public static function localBound():Int {
		localReads = 0;
		var i = 0;
		var bound = 3;
		while (i < readLocal(bound)) {
			i++;
			bound = bound + 0; // deliberate local-bound reassignment
		}
		return localReads;
	}

	public static function growingLength():Int {
		lengthReads = 0;
		var i = 0;
		var values = [0];
		while (i < readLength(values)) {
			i++;
			if (i == 1) values.push(0); // length grows once while running
		}
		return lengthReads;
	}

	public static function doubleControl():Int {
		localReads = 0;
		var i = 0;
		var bound = 1;
		while (i < readLocal(bound)) {
			i++;
		}
		while (i < readLocal(bound + 1)) {
			i++;
		}
		return localReads;
	}

	public static function main():Void {
		trace('local=' + localBound() + ' length=' + growingLength() + ' control=' + doubleControl());
	}
}
