package probeE;

import std.ReadOnlyArray;

enum PEChoice {
	One;
	Two;
}

enum PEKind {
	EOnly(tag:String);
}

class PEError extends haxe.Exception {
	public final kind:PEKind;

	public function new() {
		this.kind = EOnly("e");
		super("pe");
	}
}

class PESources {
	public static function arr1():Array<Int>
		return [1, 2];

	public static function arr2():Array<Int>
		return [3];

	public static function consume(v:ReadOnlyArray<Int>):Int
		return v.length;
}

class PELambda {
	// enclosing member returns Int; the lambda returns ReadOnlyArray<Int>.
	// multi-statement body so the return goes through stmtLines
	public static function lambdaTryReturn(flag:Bool):Int {
		var f = function(flag:Bool):ReadOnlyArray<Int> {
			if (flag) throw new PEError();
			return try {
				PESources.arr1();
			} catch (e:PEError) {
				PESources.arr2();
			}
		}
		return PESources.consume(f(flag));
	}

	// single-statement body: return switch
	public static function lambdaSwitchReturn(c:PEChoice):Int {
		var f = function(c:PEChoice):ReadOnlyArray<Int> {
			return switch (c) {
				case One: PESources.arr1();
				case Two: PESources.arr2();
			}
		}
		return PESources.consume(f(c));
	}

	// try binding INSIDE a lambda: destination is the local's declared type
	public static function lambdaTryBinding(flag:Bool):Int {
		var f = function(flag:Bool):Int {
			if (flag) throw new PEError();
			var view:ReadOnlyArray<Int> = try {
				PESources.arr1();
			} catch (e:PEError) {
				PESources.arr2();
			}
			return PESources.consume(view);
		}
		return f(flag);
	}

	// control: lambda returns the mutable array it was given
	public static function lambdaPlain(values:Array<Int>):Int {
		var f = function():Array<Int> {
			return values;
		}
		var view:ReadOnlyArray<Int> = f();
		return PESources.consume(view);
	}
}
