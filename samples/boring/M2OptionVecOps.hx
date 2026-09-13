package boring;

#if rust_output
import std.SortedMap;
import std.SortedSet;

/**
 * Reproduces two rust E0599 families: methods called on nullable (Option)
 * receivers, and Haxe Array methods that Rust Vec names differently
 * (copy/shift/unshift/indexOf). A local declared with a non-nullable type
 * but initialized from a null-guarded path holds the proven inner value
 * (guarded-copy local family), so field reads must not address the Option.
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

    public static function copyArray(src:Array<String>):String {
        final copy = src.copy();
        return copy.join(",");
    }

    public static function shiftArray(src:Array<String>):String {
        final shifted = src.shift();
        if (shifted == null) return ":" + src.join(",");
        return shifted + ":" + src.join(",");
    }

    public static function unshiftArray(src:Array<String>, v:String):String {
        src.unshift(v);
        return src.join(",");
    }

    public static function indexOfArray(src:Array<String>, needle:String):String {
        return Std.string(src.indexOf(needle));
    }

    public static function guardedCopyWidth(rect:Null<GuardedRect>):Float {
        if (rect != null) {
            final r:GuardedRect = rect;
            return r.left + r.top;
        }
        return 0.0;
    }

    public static function guardedCopyFieldWidth(box:GuardedBox):Float {
        if (box.rect != null) {
            final r:GuardedRect = box.rect;
            return r.left + r.top;
        }
        return 0.0;
    }

    public static function guardedAndSpan(pair:Null<GuardedRect>, end:Float):Float {
        if (pair != null && pair.left < end) {
            return pair.left + 1.0;
        }
        return 0.0;
    }

    public static function guardedHolderSpan(box:GuardedBox):Float {
        if (box.rect != null) {
            final r:GuardedRect = box.rect;
            return r.left + r.top;
        }
        return 0.0;
    }
}
#else
class M2OptionVecOps {}
#end