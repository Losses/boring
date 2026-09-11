package boring;

#if swift_output
import std.SortedMap;

/**
    A non-null static map field initialized to null. Swift rejects a nil
    initializer for a plain stored type, so the declaration carries an
    implicitly unwrapped optional while reads stay plain.
*/
class NullStaticMapOps {
    private static var cache:SortedMap<Int, String> = null;
    private static var builder = null;

    public static function lookup(k:Int):Null<String> {
        if (builder == null) {
            builder = SortedMap.builder();
            cache = builder.build();
        }
        return cache.get(k);
    }
}
#else
class NullStaticMapOps {}
#end
