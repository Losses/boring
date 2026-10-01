package probeD;

import std.ReadOnlyArray;

enum PDKind {
	DOnly(tag:String);
}

class PDError extends haxe.Exception {
	public final kind:PDKind;

	public function new() {
		this.kind = DOnly("d");
		super("pd");
	}
}

class PDSources {
	public static var effects:Int = 0;

	public static function arr1():Array<Int> {
		effects += 1;
		return [1, 2];
	}

	public static function arr2():Array<Int> {
		effects += 2;
		return [3];
	}

	public static function consume(v:ReadOnlyArray<Int>):Int
		return v.length;
}

class PDTryShapes {
	public static function tryEffectful(flag:Bool):Int {
		var view:ReadOnlyArray<Int> = try {
			if (flag) throw new PDError();
			PDSources.arr1();
		} catch (e:PDError) {
			PDSources.arr2();
		}
		return PDSources.consume(view);
	}
}
