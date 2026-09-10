package boring;

#if rust_output
import std.SortedMap;
import std.SortedSet;

/**
 * Reproduces two rust E0599 families: methods called on nullable (Option)
 * receivers, and Haxe Array methods that Rust Vec names differently
 * (copy/shift/unshift/indexOf).
 */
class M2OptionVecOps {
    public var tags:Null<Array<String>>;
    public var seen:Null<SortedSet<Int>>;
    public var index:Null<SortedMapBuilder<Int, String>>;

    public function new() {
        tags = null;
        seen = null;
        index = null;
    }

    public function addTag(s:String):String {
        if (tags == null) tags = [];
        tags.push(s);
        return tags.join(",");
    }

    public function hasSeen(i:Int):Bool {
        if (seen == null) seen = SortedSet.builder().build();
        return seen.has(i);
    }

    public function countSeen():Int {
        if (seen == null) seen = SortedSet.builder().build();
        return seen.size();
    }

    public function readIndex(k:Int):Bool {
        if (index == null) index = SortedMap.builder();
        index.put(k, "v");
        return index.get(k) == "v";
    }

    public static function copyArray(src:Array<Int>):String {
        final copy = src.copy();
        return copy.join(",");
    }

    public static function shiftArray(src:Array<Int>):String {
        final shifted = src.shift();
        if (shifted == null) return ":" + src.join(",");
        return shifted + ":" + src.join(",");
    }

    public static function unshiftArray(src:Array<Int>, v:Int):String {
        src.unshift(v);
        return src.join(",");
    }

    public static function indexOfArray(src:Array<String>, needle:String):String {
        return Std.string(src.indexOf(needle));
    }
}
#end