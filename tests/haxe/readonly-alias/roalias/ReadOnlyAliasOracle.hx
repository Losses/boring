package roalias;

import std.ReadOnlyArray;

/**
    Authored Haxe oracle for the ordinary `Array<T> -> ReadOnlyArray<T>`
    shared-container contract (feature 18 ruling). It consolidates the
    historical S, D, and X probes into one source that is generated and
    executed on all five targets by `tests/haxe/readonly-alias/run.sh`.

    Shapes and their lineage:
    - alias:    the S scalar slot-and-length encoding
                (out/architecture-alias-targets at e3b8bab3; the Haxe oracle
                printed ALIAS=702 and TS/Kotlin/Dart observed 702).
    - passed:   the call-boundary encoding the D probe left as an open
                position (out/architecture-readonly-probe at e3b8bab3;
                ordinary call-position aliasing was never observed).
    - escaped:  the X view-only escape lifetime (tests/haxe/view-lifetime
                case 2 at c9e2cff9; never executed).
    - rebind:   the X binding-reassignment discriminator (case 1).
    - boundary: the X cross-boundary holder mutation (case 4, encoding
                564:1494).

    The expected values are the feature 18 shared-container reading:
    alias=702 passed=3301 escaped=56 rebind=123 boundary=564:1494.
**/
class ReadOnlyAliasOracle {
	/**
	    Shape 1 (alias): a local container is converted, then a retained
	    mutable alias mutates the slot and appends. A shared view reports
	    7 * 100 + 2 = 702; a snapshot taken at the conversion reports
	    1 * 100 + 1 = 101.
	**/
	public static function alias():Int {
		var mutable:Array<Int> = [1];
		final view:ReadOnlyArray<Int> = mutable;
		mutable[0] = 7;
		mutable.push(9);
		return view[0] * 100 + view.length;
	}

	/**
	    Shape 2 (passed): the plain array crosses a call boundary as a
	    read-only argument; the callee returns the parameter view and the
	    caller mutates through its retained alias before reading the view.
	    A shared argument-position conversion reports 33 * 100 + 1 = 3301;
	    a value copied at the argument or return position reports
	    12 * 100 + 1 = 1201.
	**/
	public static function passed():Int {
		var source:Array<Int> = [12];
		final view:ReadOnlyArray<Int> = passThrough(source);
		source[0] = 33;
		return view[0] * 100 + view.length;
	}

	public static function passThrough(values:ReadOnlyArray<Int>):ReadOnlyArray<Int> {
		return values;
	}

	/**
	    Shape 3 (escaped): the conversion happens at the producer's return
	    and the view is the only surviving reference; the consumer reads it
	    after the producer frame has ended. A view that retains its storage
	    reports 56 on every target.
	**/
	public static function escaped():Int {
		final view = makeView();
		return view[0] * 10 + view[1];
	}

	public static function makeView():ReadOnlyArray<Int> {
		var values:Array<Int> = [5, 6];
		return values;
	}

	/**
	    Shape 4 (rebind): the source binding is reassigned to another
	    container after the conversion. A view that retains the original
	    storage reports 123; a view that follows the binding reports 987.
	**/
	public static function rebind():Int {
		var values:Array<Int> = [1, 2, 3];
		final view:ReadOnlyArray<Int> = values;
		values = [9, 8, 7];
		return view[0] * 100 + view[1] * 10 + view[2];
	}

	/**
	    Shape 5 (boundary): the producer returns the view together with a
	    holder retaining a mutable alias to the ORIGINAL container; the
	    binding is rebound and the replacement mutated inside the producer
	    before the return. After the producer frame has ended, the retained
	    alias mutates the original. A shared view reports
	    564:1494; a view detached from the holder's container reports
	    564:564.
	**/
	public static function boundary():String {
		final result = boundaryProducer();
		final before = result.view[0] * 100 + result.view[1] * 10 + result.view[2];
		result.holder.values[1] = 99;
		final after = result.view[0] * 100 + result.view[1] * 10 + result.view[2];
		return before + ":" + after;
	}

	public static function boundaryProducer():BoundaryResult {
		var values:Array<Int> = [5, 6, 4];
		final original:AliasHolder = new AliasHolder(values);
		final view:ReadOnlyArray<Int> = values;
		values = [9, 8, 7];
		values[0] = 77;
		return new BoundaryResult(view, original);
	}

	/**
	    The Haxe JS oracle entry. Native harnesses call the five shape
	    functions directly and print the same labeled lines; the generated
	    trees for native targets keep an empty main so the fixture adds no
	    target-specific console dependency.
	**/
	public static function main():Void {
		#if js
		std.Console.log("alias=" + alias());
		std.Console.log("passed=" + passed());
		std.Console.log("escaped=" + escaped());
		std.Console.log("rebind=" + rebind());
		std.Console.log("boundary=" + boundary());
		#end
	}
}
