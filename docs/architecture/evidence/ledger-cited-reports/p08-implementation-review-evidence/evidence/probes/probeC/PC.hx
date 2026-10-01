package probeC;

import std.ReadOnlyArray;

enum PCChoice {
	One;
	Two;
}

class PCSources {
	public static function arr1():Array<Int>
		return [1, 2];

	public static function arr2():Array<Int>
		return [3];

	public static function consume(v:ReadOnlyArray<Int>):Int
		return v.length;
}

class PCWrappedSwitch {
	// block-expression wrapped switch
	public static function switchBindingBlock(c:PCChoice):Int {
		var view:ReadOnlyArray<Int> = {
			switch (c) {
				case One: PCSources.arr1();
				case Two: PCSources.arr2();
			}
		};
		return PCSources.consume(view);
	}

	// parenthesised switch
	public static function switchBindingParen(c:PCChoice):Int {
		var view:ReadOnlyArray<Int> = (switch (c) {
			case One: PCSources.arr1();
			case Two: PCSources.arr2();
		});
		return PCSources.consume(view);
	}
}
