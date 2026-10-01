package probeA;

import std.ReadOnlyArray;

enum PAChoice {
	One;
	Two;
}

enum PAKind {
	KOnly(tag:String);
}

class PAError extends haxe.Exception {
	public final kind:PAKind;
	public final items:Array<Int>;

	public function new(items:Array<Int>) {
		this.items = items;
		this.kind = KOnly("x");
		super("pa");
	}
}

class PASources {
	public static function arr1():Array<Int>
		return [1, 2];

	public static function arr2():Array<Int>
		return [3];

	public static function maybeArr():Null<Array<Int>>
		return null;

	public static function consume(v:ReadOnlyArray<Int>):Int
		return v.length;
}

class PACatchRef {
	// handler arm value MENTIONS the caught exception binding and crosses the boundary
	public static function tryBindingCatchRef(flag:Bool):Int {
		var view:ReadOnlyArray<Int> = try {
			if (flag) throw new PAError([7]);
			PASources.arr1();
		} catch (e:PAError) {
			e.items;
		}
		return PASources.consume(view);
	}

	public static function tryReturnCatchRef(flag:Bool):ReadOnlyArray<Int> {
		return try {
			if (flag) throw new PAError([7]);
			PASources.arr1();
		} catch (e:PAError) {
			e.items;
		}
	}
}

class PASwitchShapes {
	public static function switchBindingLocal(c:PAChoice, values:Array<Int>):Int {
		var view:ReadOnlyArray<Int> = switch (c) {
			case One: values;
			case Two: values;
		}
		return PASources.consume(view);
	}

	public static function switchAlreadyView(c:PAChoice, v:ReadOnlyArray<Int>):Int {
		var view:ReadOnlyArray<Int> = switch (c) {
			case One: v;
			case Two: v;
		}
		return PASources.consume(view);
	}

	public static function switchBindingEmptyArms(c:PAChoice):Int {
		var view:ReadOnlyArray<Int> = switch (c) {
			case One: [1];
			case Two: [];
		}
		return PASources.consume(view);
	}
}

class PAHolder {
	public var slot:Null<ReadOnlyArray<Int>>;

	public function new() {
		this.slot = null;
	}
}

class PASwitchAssignNullable {
	public static function switchAssignNullable(c:PAChoice, h:PAHolder):Void {
		h.slot = switch (c) {
			case One: PASources.arr1();
			case Two: PASources.arr2();
		}
	}

	public static function switchStmtAssignField(c:PAChoice, h:PAHolder):Void {
		switch (c) {
			case One: h.slot = PASources.arr1();
			case Two: h.slot = PASources.arr2();
		}
	}
}
