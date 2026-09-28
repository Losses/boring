package place;

import std.Console;

/**
	Paired observation module for the place contract. The same authored
	operations run on the pinned Haxe runner through `PlaceStaticMain` and
	are generated for Rust through `rust-gen.hxml`.

	Each case can be generated on its own with `-D placeSplit` plus one
	case define (`placeR1`, `placeR2`, `placeR3`, `placeR5`, `placeR5rec`,
	`placeR6`). Without `placeSplit` every case is generated, which is the
	form the Haxe entry runs. The record case `placeR5rec` is authored and
	labelled separately from the class case `placeR5`.
**/
class PlaceObserveStatic {
	var a:Array<Int>;
	var box:PlaceBox;
	var shelf:Shelf;
	var outer:OuterMid;

	public function new() {
		a = [10, 20];
		box = new PlaceBox([10, 20]);
		shelf = new Shelf([10, 20]);
		outer = new OuterMid(new PlaceInner(1), new PlaceInner(2), [new PlaceInner(1), new PlaceInner(2)]);
	}

	public function run():Void {
		#if (placeR1 || !placeSplit)
		fieldElementCompound();
		#end
		#if (placeR2 || !placeSplit)
		nestedContainerCompound();
		#end
		#if (placeR3 || !placeSplit)
		getterElementCompound();
		#end
		#if (placeR5 || !placeSplit)
		classIntermediateCompound();
		#end
		#if (placeR5rec || !placeSplit)
		recordIntermediateCompound();
		#end
		#if (placeR6 || !placeSplit)
		finalFieldElement();
		#end
	}

	// R1: the element compound whose right side rebinds the field binding.
	#if (placeR1 || !placeSplit)
	function fieldElementCompound():Void {
		a = [10, 20];
		final original:Array<Int> = a;
		a[0] += rebindField();
		Console.log('R1 a[0]=${a[0]} a.length=${a.length} original[0]=${original[0]}');
	}

	function rebindField():Int {
		a = [90, 91, 92];
		return 7;
	}
	#end

	// R2: the nested container compound whose right side replaces the box.
	#if (placeR2 || !placeSplit)
	function nestedContainerCompound():Void {
		box = new PlaceBox([10, 20]);
		final original:Array<Int> = box.value;
		box.value[0] += rebindBox();
		Console.log('R2 box.value[0]=${box.value[0]} original[0]=${original[0]}');
	}

	function rebindBox():Int {
		box = new PlaceBox([70, 71]);
		return 5;
	}
	#end

	// R3: the element compound through a getter-only property.
	#if (placeR3 || !placeSplit)
	function getterElementCompound():Void {
		shelf = new Shelf([10, 20]);
		shelf.items[0] += 3;
		Console.log('R3 shelf.items[0]=${shelf.items[0]}');
	}
	#end

	// R5: value intermediates through ordinary classes with a later read.
	#if (placeR5 || !placeSplit)
	function classIntermediateCompound():Void {
		outer = new OuterMid(new PlaceInner(1), new PlaceInner(2), [new PlaceInner(1), new PlaceInner(2)]);
		outer.inner.n = 5;
		outer.items[0].n += 1;
		outer.mid.inner.n += 3;
		Console.log('R5 inner=${outer.inner.n} item=${outer.items[0].n} deep=${outer.mid.inner.n}');
	}
	#end

	// R5rec: the same three operations over typedef records. Authored and
	// labelled separately from R5; feature 38 ruling 4 covers records on
	// the Rust target and says nothing about the classes of R5.
	#if (placeR5rec || !placeSplit)
	function recordIntermediateCompound():Void {
		final outer:RecOuter = {inner: {n: 1}, mid: {inner: {n: 2}}, items: [{n: 1}, {n: 2}]};
		outer.inner.n = 5;
		outer.items[0].n += 1;
		outer.mid.inner.n += 3;
		Console.log('R5rec inner=${outer.inner.n} item=${outer.items[0].n} deep=${outer.mid.inner.n}');
	}
	#end

	// R6: element mutation through a final field binding.
	#if (placeR6 || !placeSplit)
	function finalFieldElement():Void {
		final bucket = new Bucket([30, 40]);
		bucket.items.push(41);
		Console.log('R6 bucket.items.length=${bucket.items.length}');
	}
	#end
}

class PlaceBox {
	public var value:Array<Int>;

	public function new(value:Array<Int>) {
		this.value = value;
	}
}

class PlaceInner {
	public var n:Int;

	public function new(n:Int) {
		this.n = n;
	}
}

class MiddleBox {
	public var inner:PlaceInner;

	public function new(inner:PlaceInner) {
		this.inner = inner;
	}
}

class OuterMid {
	public var inner:PlaceInner;
	public var mid:MiddleBox;
	public var items:Array<PlaceInner>;

	public function new(inner:PlaceInner, deep:PlaceInner, items:Array<PlaceInner>) {
		this.inner = inner;
		this.mid = new MiddleBox(deep);
		this.items = items;
	}
}

class Shelf {
	public var backing:Array<Int>;
	public var items(get, never):Array<Int>;

	public function new(items:Array<Int>) {
		backing = items;
	}

	function get_items():Array<Int> {
		return backing;
	}
}

class Bucket {
	public final items:Array<Int>;

	public function new(items:Array<Int>) {
		this.items = items;
	}
}

// Record types of R5rec, declared as subtypes of this module so the
// record case stays inside the same authored source.
typedef RecInner = {n:Int};

typedef RecMiddle = {inner:RecInner};

typedef RecOuter = {inner:RecInner, mid:RecMiddle, items:Array<RecInner>};
