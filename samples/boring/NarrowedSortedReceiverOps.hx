package boring;

#if rust_output
import std.SortedMap;
import std.SortedSet;

/**
    A nullable sorted container read in a null-coalescing ternary. The
    true branch calls a container method through the match binding, which
    is already the inner table reference; the forcing read must not ask
    Rust to find AsRef on the table type.
*/
class NarrowedSortedReceiverOps {
    public static function hasKey(values:Null<SortedMap<String, Int>>, key:String):Bool {
        return values != null ? values.has(key) : false;
    }

    public static function sizeOrZero(values:Null<SortedSet<Int>>):Int {
        return values != null ? values.size() : 0;
    }

}
#else
class NarrowedSortedReceiverOps {}
#end
