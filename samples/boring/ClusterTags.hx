package boring;

import std.SortedMap;
import std.SortedSet;

typedef SubTag = {
	final priority:Int;
}

typedef ClusterTag = {
	final name:String;
	final score:Int;
	final sub:SubTag;
	final active:Bool;
}

/**
 * Sample demonstrating std.SortedMap and std.SortedSet with structure keys
 * (docs/specs/stdlib/07-sorted-keyed-tables.md).
 */
class ClusterTags {
	public static function createMap():SortedMap<ClusterTag, Int> {
		final b:SortedMapBuilder<ClusterTag, Int> = SortedMap.builder();
		b.put({name: "beta", score: 10, sub: {priority: 1}, active: true}, 100);
		b.put({name: "alpha", score: 20, sub: {priority: 2}, active: false}, 200);
		b.put({name: "alpha", score: 10, sub: {priority: 3}, active: true}, 300);
		b.put({name: "alpha", score: 10, sub: {priority: 1}, active: true}, 400);
		b.put({name: "alpha", score: 10, sub: {priority: 1}, active: false}, 500);
		return b.build();
	}

	public static function createSet():SortedSet<ClusterTag> {
		final b:SortedSetBuilder<ClusterTag> = SortedSet.builder();
		b.put({name: "beta", score: 10, sub: {priority: 1}, active: true});
		b.put({name: "alpha", score: 10, sub: {priority: 1}, active: false});
		b.put({name: "beta", score: 10, sub: {priority: 1}, active: true});
		b.put({name: "alpha", score: 20, sub: {priority: 2}, active: false});
		return b.build();
	}

	public static function tagScore(tag:ClusterTag):Null<Int> {
		final map = createMap();
		return map.get(tag);
	}

	public static function describeOrder():String {
		final map = createMap();
		final parts:Array<String> = [];
		final count = map.size();
		for (i in 0...count) {
			final k = map.keyAt(i);
			var act = "F";
			if (k.active) {
				act = "T";
			}
			parts.push(k.name + ":" + k.score + ":" + k.sub.priority + ":" + act + "=" + map.valueAt(i));
		}
		return parts.join("; ");
	}

	public static function describeSetOrder():String {
		final set = createSet();
		final parts:Array<String> = [];
		final count = set.size();
		for (i in 0...count) {
			final k = set.at(i);
			var act = "F";
			if (k.active) {
				act = "T";
			}
			parts.push(k.name + ":" + k.score + ":" + k.sub.priority + ":" + act);
		}
		return parts.join("; ");
	}
}
