package runtime;

import std.UStringPlatform;

/**
	Sorted keyed tables, the single source behind std.SortedMap and
	std.SortedSet (docs/specs/stdlib/07-sorted-keyed-tables.md). The immutable tables
	hold parallel arrays sorted by key; the builders accumulate puts and
	apply the last-put-wins rule at build().

	One generic source replaces the three per-domain families the lanes
	hand-wrote before. The comparator is a function value bound when the
	builder is created: the compiler passes the resident integer
	comparator, the resident string comparator, or a per-type generated
	structure comparator. The extern faces in samples/std/SortedMap.hx and
	samples/std/SortedSet.hx keep their names; every target lowers
	references to them onto these classes.

	The storage is Array<K> on every target. Kotlin boxes integer keys
	this way; the previous hand-written shim held an IntArray. The cost is
	one object per integer key inside a table, accepted for one source.
**/
/**
	Key comparator bound at builder creation: negative when left sorts
	first, zero on equal keys, positive when right sorts first.
**/
typedef SortedTableCompare<K> = (left:K, right:K) -> Int;

class SortedTable {
	/**
		Ordering of integers: negative when a sorts before b, positive when
		a sorts after b, zero on equality.
	**/
	public static function compareInts(a:Int, b:Int):Int {
		if(a < b) {
			return -1;
		}
		if(a > b) {
			return 1;
		}
		return 0;
	}

	/**
		Ordering of strings in UTF-16 code-unit order, the order spec 07
		rules. The walk advances by code point; at the first differing
		code point, unit order and code-point order agree except when one
		side is astral and the other is a BMP code point at or above
		0xE000: the astral side's leading surrogate (0xD800..0xDBFF) sorts
		below every unit at or above 0xE000, so the astral side comes
		first. Keys are valid Unicode scalar sequences (spec 07), so no
		other adjustment exists.
	**/
	public static function compareStrings(a:String, b:String):Int {
		final endA = UStringPlatform.end(a);
		final endB = UStringPlatform.end(b);
		var indexA = 0;
		var indexB = 0;
		while(indexA < endA && indexB < endB) {
			final codeA = UStringPlatform.codeAt(a, indexA);
			final codeB = UStringPlatform.codeAt(b, indexB);
			if(codeA != codeB) {
				if(codeA >= 0xE000 && codeA < 0x10000 && codeB >= 0x10000) {
					return 1;
				}
				if(codeB >= 0xE000 && codeB < 0x10000 && codeA >= 0x10000) {
					return -1;
				}
				if(codeA < codeB) {
					return -1;
				}
				return 1;
			}
			indexA = UStringPlatform.advance(a, indexA);
			indexB = UStringPlatform.advance(b, indexB);
		}
		if(indexA < endA) {
			return 1;
		}
		if(indexB < endB) {
			return -1;
		}
		return 0;
	}

	/** Create a map builder ordered by `compare`. */
	public static function mapBuilder<K, V>(compare:SortedTableCompare<K>):SortedMapTableBuilder<K, V> {
		return new SortedMapTableBuilder<K, V>(new Array<K>(), new Array<V>(), compare);
	}

	/** Create a set builder ordered by `compare`. */
	public static function setBuilder<K>(compare:SortedTableCompare<K>):SortedSetTableBuilder<K> {
		return new SortedSetTableBuilder<K>(new Array<K>(), compare);
	}
}

/**
	Immutable map: keys and values in parallel arrays, keys sorted by the
	comparator bound at construction.
**/
class SortedMapTable<K, V> {
	final keys:Array<K>;
	final values:Array<V>;
	final compare:SortedTableCompare<K>;

	public function new(keys:Array<K>, values:Array<V>, compare:SortedTableCompare<K>) {
		this.keys = keys;
		this.values = values;
		this.compare = compare;
	}

	/** The value stored under `key`, or null when absent. */
	public function get(key:K):Null<V> {
		final index = locate(key);
		if(index < 0) {
			return null;
		}
		return values[index];
	}

	/** Whether `key` is present. */
	public function has(key:K):Bool {
		return locate(key) >= 0;
	}

	/** The number of entries. */
	public function size():Int {
		return keys.length;
	}

	/** The key at `index`; the index must be within range. */
	public function keyAt(index:Int):K {
		return keys[index];
	}

	/** The value at `index`; the index must be within range. */
	public function valueAt(index:Int):V {
		return values[index];
	}

	/**
		Binary search for `key` over the half-open range [0, length):
		its index when present, minus one when absent. The half-open
		form never subtracts from an empty range, which the Rust lowering
		of length would evaluate on an unsigned index type.
	**/
	function locate(key:K):Int {
		var low = 0;
		var high = keys.length;
		while(low < high) {
			final mid = (low + high) >> 1;
			final order = compare(keys[mid], key);
			if(order < 0) {
				low = mid + 1;
			} else if(order > 0) {
				high = mid;
			} else {
				return mid;
			}
		}
		return -1;
	}
}

/**
	Map builder: keys and values accumulate in parallel arrays;
	build() sorts them and keeps the last put of each equal-key run.
**/
class SortedMapTableBuilder<K, V> {
	final keys:Array<K>;
	final values:Array<V>;
	final compare:SortedTableCompare<K>;

	public function new(keys:Array<K>, values:Array<V>, compare:SortedTableCompare<K>) {
		this.keys = keys;
		this.values = values;
		this.compare = compare;
	}

	/** Store `value` under `key`; a later put with the same key wins. */
	public function put(key:K, value:V):Void {
		keys.push(key);
		values.push(value);
	}

	/**
		The value of the latest put under `key`, or null when absent.
		The walk counts down from the length. For an empty builder, this
		avoids an unsigned Rust index below zero before the first comparison.
	**/
	public function get(key:K):Null<V> {
		var index = keys.length;
		while(index > 0) {
			index -= 1;
			if(compare(keys[index], key) == 0) {
				return values[index];
			}
		}
		return null;
	}

	/**
		Sort the puts into one immutable table. The sort permutes entry
		indices so values of parameter type are only read, never moved;
		equal keys keep their put order, and each equal-key run emits its
		final entry, which is the last put.
	**/
	public function build():SortedMapTable<K, V> {
		final total = keys.length;
		final order = new Array<Int>();
		var i = 0;
		while(i < total) {
			order.push(i);
			i += 1;
		}
		i = 1;
		while(i < total) {
			final current = order[i];
			var j = i;
			var moved = true;
			while(j > 0 && moved) {
				if(compare(keys[order[j - 1]], keys[current]) > 0) {
					order[j] = order[j - 1];
					j -= 1;
				} else {
					moved = false;
				}
			}
			order[j] = current;
			i += 1;
		}
		final outKeys = new Array<K>();
		final outValues = new Array<V>();
		i = 0;
		while(i < total) {
			var run = i;
			while(run + 1 < total && compare(keys[order[run + 1]], keys[order[i]]) == 0) {
				run += 1;
			}
			outKeys.push(keys[order[run]]);
			outValues.push(values[order[run]]);
			i = run + 1;
		}
		return new SortedMapTable<K, V>(outKeys, outValues, compare);
	}
}

/**
	Immutable set: keys in one array, sorted by the comparator bound at
	construction.
**/
class SortedSetTable<K> {
	final keys:Array<K>;
	final compare:SortedTableCompare<K>;

	public function new(keys:Array<K>, compare:SortedTableCompare<K>) {
		this.keys = keys;
		this.compare = compare;
	}

	/** Whether `key` is present. */
	public function has(key:K):Bool {
		return locate(key) >= 0;
	}

	/** The number of elements. */
	public function size():Int {
		return keys.length;
	}

	/** The element at `index`; the index must be within range. */
	public function at(index:Int):K {
		return keys[index];
	}

	/**
		Binary search for `key` over the half-open range [0, length):
		its index when present, minus one when absent. The half-open
		form never subtracts from an empty range, which the Rust lowering
		of length would evaluate on an unsigned index type.
	**/
	function locate(key:K):Int {
		var low = 0;
		var high = keys.length;
		while(low < high) {
			final mid = (low + high) >> 1;
			final order = compare(keys[mid], key);
			if(order < 0) {
				low = mid + 1;
			} else if(order > 0) {
				high = mid;
			} else {
				return mid;
			}
		}
		return -1;
	}
}

/**
	Set builder: keys accumulate; build() sorts them and keeps one entry
	per equal-key run.
**/
class SortedSetTableBuilder<K> {
	final keys:Array<K>;
	final compare:SortedTableCompare<K>;

	public function new(keys:Array<K>, compare:SortedTableCompare<K>) {
		this.keys = keys;
		this.compare = compare;
	}

	/** Add `key`; a later add of an equal key wins nothing extra. */
	public function put(key:K):Void {
		keys.push(key);
	}

	/**
		Sort the puts into one immutable set. The sort permutes entry
		indices so values of parameter type are only read; equal keys
		keep their put order and each run emits its final entry.
	**/
	public function build():SortedSetTable<K> {
		final total = keys.length;
		final order = new Array<Int>();
		var i = 0;
		while(i < total) {
			order.push(i);
			i += 1;
		}
		i = 1;
		while(i < total) {
			final current = order[i];
			var j = i;
			var moved = true;
			while(j > 0 && moved) {
				if(compare(keys[order[j - 1]], keys[current]) > 0) {
					order[j] = order[j - 1];
					j -= 1;
				} else {
					moved = false;
				}
			}
			order[j] = current;
			i += 1;
		}
		final outKeys = new Array<K>();
		i = 0;
		while(i < total) {
			var run = i;
			while(run + 1 < total && compare(keys[order[run + 1]], keys[order[i]]) == 0) {
				run += 1;
			}
			outKeys.push(keys[order[run]]);
			i = run + 1;
		}
		return new SortedSetTable<K>(outKeys, compare);
	}
}
