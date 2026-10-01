package probeB;

import std.ReadOnlyArray;

enum PBChoice {
	One;
	Two;
}

enum PBMutKind {
	MOnly(tag:String);
}

class PBMutError extends haxe.Exception {
	public final kind:PBMutKind;

	public function new() {
		this.kind = MOnly("m");
		super("pb");
	}
}

class PBSources {
	public static function arr1():Array<Int>
		return [1, 2];

	public static function arr2():Array<Int>
		return [3];

	public static function ro1():ReadOnlyArray<Int>
		return [4];

	public static function consume(v:ReadOnlyArray<Int>):Int
		return v.length;
}

class PBSwitchMerge {
	// arms are nil-merges: optional Array target + empty fallback
	public static function switchBindingMerge(c:PBChoice, values:Null<Array<Int>>):Int {
		var view:ReadOnlyArray<Int> = switch (c) {
			case One: values == null ? [] : values;
			case Two: values != null ? values : [];
		}
		return PBSources.consume(view);
	}
}

class PBSwitchNullableDest {
	// declared destination is Null<ReadOnlyArray<Int>>
	public static function switchBindingNullable(c:PBChoice):Int {
		var view:Null<ReadOnlyArray<Int>> = switch (c) {
			case One: PBSources.arr1();
			case Two: PBSources.arr2();
		}
		return view == null ? 0 : PBSources.consume(view);
	}
}

class PBSwitchViaLocal {
	// switch has NO expected type: sw.t should be the mutable Array
	public static function switchViaLocal(c:PBChoice):Int {
		var tmp = switch (c) {
			case One: PBSources.arr1();
			case Two: PBSources.arr2();
		}
		var view:ReadOnlyArray<Int> = tmp;
		return PBSources.consume(view);
	}
}
