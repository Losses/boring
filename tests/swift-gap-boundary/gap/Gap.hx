package gap;

import std.ReadOnlyArray;

enum GapChoice {
	One;
	Two;
}

enum GapFault {
	Only(tag:String);
}

class GapException extends haxe.Exception {
	public final fault:GapFault;

	public function new(fault:GapFault) {
		this.fault = fault;
		super(GapException.describe(fault));
	}

	public static function describe(f:GapFault):String {
		return switch (f) {
			case Only(tag): tag;
		};
	}
}

class Gap {
	public static function sourceFirst():Array<Int>
		return [1, 2];

	public static function sourceSecond():Array<Int>
		return [3];

	// CONTROL: ternary initializer, destination ReadOnlyArray.
	public static function controlTernary(flag:Bool):Int {
		var view:ReadOnlyArray<Int> = flag ? sourceFirst() : sourceSecond();
		return view.length;
	}

	// GAP CANDIDATE A: switch initializer, destination ReadOnlyArray.
	public static function switchLocal(choice:GapChoice):Int {
		var view:ReadOnlyArray<Int> = switch (choice) {
			case One: sourceFirst();
			case Two: sourceSecond();
		};
		return view.length;
	}

	// GAP CANDIDATE B: try initializer, destination ReadOnlyArray.
	public static function tryLocal(flag:Bool):Int {
		var view:ReadOnlyArray<Int> = try {
			if (flag) throw new GapException(GapFault.Only("boom"));
			sourceFirst();
		} catch (e:GapException) {
			sourceSecond();
		}
		return view.length;
	}

	// CONTRAST: switch in return position; currentReturnType is ReadOnlyArray.
	public static function switchReturnPosition(choice:GapChoice):ReadOnlyArray<Int> {
		return switch (choice) {
			case One: sourceFirst();
			case Two: sourceSecond();
		};
	}
}

class GapExtra {
	// CONTRAST 2: switch in return position, arm value is a plain local.
	public static function switchReturnLocal(choice:GapChoice, values:Array<Int>):ReadOnlyArray<Int> {
		return switch (choice) {
			case One: values;
			case Two: values;
		};
	}

	// CONTROL 2: ternary in return position.
	public static function ifReturnPosition(flag:Bool):ReadOnlyArray<Int> {
		return flag ? Gap.sourceFirst() : Gap.sourceSecond();
	}

	// GAP CANDIDATE C: switch expression as an argument (expression position).
	public static function switchArgument(choice:GapChoice):Int {
		return consume(switch (choice) {
			case One: Gap.sourceFirst();
			case Two: Gap.sourceSecond();
		});
	}

	public static function consume(view:ReadOnlyArray<Int>):Int {
		return view.length;
	}
}

class GapStatics {
	// Static read-only array field: routes through SwiftDecl's own
	// prepare/render calls, not through lowerArrayBoundary.
	public static final values:ReadOnlyArray<Int> = [41];
}

class GapExplicitReturn {
	// A switch arm written with an explicit `return` statement.
	public static function switchExplicitReturn(choice:GapChoice):ReadOnlyArray<Int> {
		switch (choice) {
			case One: return Gap.sourceFirst();
			case Two: return Gap.sourceSecond();
		}
		return Gap.sourceFirst();
	}
}

class GapPaths {
	static var slot:ReadOnlyArray<Int> = [];

	// GAP CANDIDATE D: try in return position.
	public static function tryReturn(flag:Bool):ReadOnlyArray<Int> {
		return try {
			if (flag) throw new GapException(GapFault.Only("x"));
			Gap.sourceFirst();
		} catch (e:GapException) {
			Gap.sourceSecond();
		};
	}

	// GAP CANDIDATE E: assignment whose value is a switch.
	public static function switchAssignPath(choice:GapChoice):Int {
		slot = switch (choice) {
			case One: Gap.sourceFirst();
			case Two: Gap.sourceSecond();
		};
		return slot.length;
	}
}

class GapPaths2 {
	// Statement-position switch (switchStatement, call site 822).
	public static function switchStatementPath(choice:GapChoice):Int {
		var view:ReadOnlyArray<Int> = [];
		switch (choice) {
			case One: view = Gap.sourceFirst();
			case Two: view = Gap.sourceSecond();
		}
		return view.length;
	}

	// Statement-position try (tryStatementLines, call site 824). V19 bans
	// `return` inside a try body, so the crossing arrives by assignment.
	public static function tryStatementAssignPath(flag:Bool):Int {
		var view:ReadOnlyArray<Int> = [];
		try {
			if (flag) throw new GapException(GapFault.Only("y"));
			view = Gap.sourceFirst();
		} catch (e:GapException) {
			view = Gap.sourceSecond();
		}
		return view.length;
	}
}
