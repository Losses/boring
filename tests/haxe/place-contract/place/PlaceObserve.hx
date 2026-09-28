package place;

import std.Console;
import std.ReadOnlyArray;

/**
	Diagnostic observation of accepted assignment and access forms on the
	pinned Haxe runner. Every case prints its own trace with distinct marker
	values. The program records observations; it asserts no compiler contract
	and no policy rule.
**/
class PlaceObserve {
	static var events:StringBuf = new StringBuf();
	static var receiverRuns:Int = 0;
	static var indexRuns:Int = 0;
	static var rhsRuns:Int = 0;
	static var getterReads:Int = 0;

	static function note(event:String):Void {
		events.add(event);
		events.add(" ");
	}

	static function resetCounters():Void {
		receiverRuns = 0;
		indexRuns = 0;
		rhsRuns = 0;
		getterReads = 0;
	}

	static function flushEvents(label:String):Void {
		Console.log('  events: ${events.toString()}');
		events = new StringBuf();
	}

	static function counters(label:String, shelf:Null<Shelf>):Void {
		final reads = shelf == null ? 0 : shelf.reads;
		Console.log('  $label receiver=$receiverRuns index=$indexRuns rhs=$rhsRuns getterReads=$reads');
	}

	static function show(label:String, text:String):Void {
		Console.log('  $label $text');
	}

	static function heading(label:String):Void {
		Console.log('[$label]');
	}

	static function main():Void {
		caseLocalRebind();
		caseGetterReceiverRebind();
		caseNestedContainerRebind();
		caseNestedValueIntermediates();
		caseThrowingRightSide();
		caseOutOfRangeElement();
		caseAccessorAndFinalPermission();
		caseReadOnlyAlias();
	}

	// C1: a local array binding whose right side rebinds the binding itself.
	static function caseLocalRebind():Void {
		heading("C1 local element compound, right side rebinds the binding");
		resetCounters();
		var a:Array<Int> = [10, 20];
		final original:Array<Int> = a;
		final rebind:() -> Int = function():Int {
			rhsRuns++;
			note("rhs-enter");
			a = [90, 91, 92];
			note("rebind-done");
			return 7;
		}
		final index:() -> Int = function():Int {
			indexRuns++;
			note("index-eval");
			return 0;
		}
		a[index()] += rebind();
		note("statement-done");
		show("original[0]", Std.string(original[0]));
		show("original[1]", Std.string(original[1]));
		show("bound-a[0]", Std.string(a[0]));
		show("bound-a-length", Std.string(a.length));
		counters("counts", null);
		flushEvents("C1");
	}

	// C1b: the receiver read is a getter, so the read and the store both count.
	static function caseGetterReceiverRebind():Void {
		heading("C1b getter receiver, right side replaces the backing array");
		resetCounters();
		final shelf = new Shelf([10, 20]);
		final original:Array<Int> = shelf.backing;
		final rebind:() -> Int = function():Int {
			rhsRuns++;
			note("rhs-enter");
			shelf.backing = [90, 91];
			note("backing-replaced");
			return 7;
		}
		shelf.reads = 0;
		shelf.items[0] += rebind();
		note("statement-done");
		show("old-backing[0]", Std.string(original[0]));
		show("old-backing[1]", Std.string(original[1]));
		show("new-backing[0]", Std.string(shelf.backing[0]));
		show("new-backing[1]", Std.string(shelf.backing[1]));
		counters("counts", shelf);
		flushEvents("C1b");
	}

	// C2: nested container with receiver and index side effects.
	static function caseNestedContainerRebind():Void {
		heading("C2 nested container element compound with receiver and index effects");
		resetCounters();
		final holder = new Holder({value: [10, 20]});
		final original:Array<Int> = holder.box.value;
		final replaceBox:() -> Int = function():Int {
			rhsRuns++;
			note("rhs-enter");
			holder.box = {value: [70, 71]};
			note("box-replaced");
			return 5;
		}
		final index:() -> Int = function():Int {
			indexRuns++;
			note("index-eval");
			return 0;
		}
		final receiver:() -> Holder = function():Holder {
			receiverRuns++;
			note("receiver-eval");
			return holder;
		}
		receiver().box.value[index()] += replaceBox();
		note("statement-done");
		show("original-box-value[0]", Std.string(original[0]));
		show("current-box-value[0]", Std.string(holder.box.value[0]));
		counters("counts", null);
		flushEvents("C2");
	}

	// C5: record and nested record intermediates with later reads.
	static function caseNestedValueIntermediates():Void {
		heading("C5 record intermediates and later reads");
		resetCounters();
		final outer:Mid = {inner: {n: 1}, mid: {inner: {n: 2}}, items: [{n: 1}, {n: 2}]};
		outer.inner.n = 5;
		show("after field store", 'outer.inner.n=${outer.inner.n}');
		outer.items[0].n = 6;
		show("after element store", 'outer.items[0].n=${outer.items[0].n}');
		outer.items[1] = {n: 9};
		outer.items[1].n += 1;
		show("after replacement and compound", 'outer.items[1].n=${outer.items[1].n}');
		outer.mid.inner.n += 3;
		show("after three-level compound", 'outer.mid.inner.n=${outer.mid.inner.n}');
		flushEvents("C5");
	}

	// C3: a throwing right side after the target read.
	static function caseThrowingRightSide():Void {
		heading("C3 throwing right side");
		resetCounters();
		final shelf = new Shelf([10, 20]);
		shelf.reads = 0;
		final thrower:() -> Int = function():Int {
			rhsRuns++;
			note("rhs-enter");
			throw new PlaceFault("right side fault");
		}
		try {
			shelf.items[0] += thrower();
			note("store-done");
		} catch (fault:PlaceFault) {
			note("caught");
		}
		show("shelf-backing[0]", Std.string(shelf.backing[0]));
		show("shelf-backing[1]", Std.string(shelf.backing[1]));
		counters("counts", shelf);
		flushEvents("C3a");

		resetCounters();
		var a:Array<Int> = [30, 40];
		final throwerPlain:() -> Int = function():Int {
			rhsRuns++;
			note("rhs-enter");
			throw new PlaceFault("right side fault");
		}
		try {
			a[0] += throwerPlain();
			note("store-done");
		} catch (fault:PlaceFault) {
			note("caught");
		}
		show("plain-a[0]", Std.string(a[0]));
		counters("counts", null);
		flushEvents("C3b");
	}

	// C3c: an out of range element read on the pinned runner.
	static function caseOutOfRangeElement():Void {
		heading("C3c out of range element compound");
		resetCounters();
		final a:Array<Int> = [10, 20];
		a[5] += 3;
		show("length-after", Std.string(a.length));
		show("a[5]", Std.string(a[5]));
		flushEvents("C3c");
	}

	// C4: element mutation through a getter and through a final field.
	static function caseAccessorAndFinalPermission():Void {
		heading("C4 element mutation through getter and final field");
		resetCounters();
		final shelf = new Shelf([10, 20]);
		shelf.reads = 0;
		shelf.items[0] = 11;
		final readsAfterStore = shelf.reads;
		show("getter-reads-after-store", Std.string(readsAfterStore));
		show("getter-element-store", 'shelf.items[0]=${shelf.items[0]}');
		final bucket = new Bucket([30, 40]);
		bucket.items.push(41);
		show("final-field-element-push", 'bucket.items.length=${bucket.items.length}');
		counters("counts", shelf);
		flushEvents("C4");
	}

	// C4b: a read-only binding over shared storage keeps alias visibility.
	static function caseReadOnlyAlias():Void {
		heading("C4b read-only binding alias visibility");
		final plain:Array<Int> = [1, 2];
		final ro:ReadOnlyArray<Int> = plain;
		plain[0] = 7;
		show("ro[0]", Std.string(ro[0]));
		show("ro.length", Std.string(ro.length));
	}
}

class Shelf {
	public var backing:Array<Int>;
	public var reads:Int = 0;
	public var items(get, never):Array<Int>;

	public function new(items:Array<Int>) {
		backing = items;
	}

	function get_items():Array<Int> {
		reads++;
		return backing;
	}
}

class Bucket {
	public final items:Array<Int>;

	public function new(items:Array<Int>) {
		this.items = items;
	}
}

class Holder {
	public var box:Box;

	public function new(box:Box) {
		this.box = box;
	}
}

class PlaceFault extends haxe.Exception {}

typedef Box = {value:Array<Int>};

typedef Inner = {n:Int};

typedef Middle = {inner:Inner};

typedef Mid = {inner:Inner, mid:Middle, items:Array<Inner>};
