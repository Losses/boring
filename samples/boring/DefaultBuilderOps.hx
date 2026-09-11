package boring;

#if swift_output
import std.SortedMap;

class DefaultBuilderSolid {
    public static final instance = new DefaultBuilderSolid();

    public function new() {}
}

/**
    Coalescing defaults that are a map builder call and a static field of a
    secondary type. The Swift default argument must lower the builder to
    `SortedTable.mapBuilder` and resolve the secondary type's module path.
*/
class DefaultBuilderOps {
    public final values:SortedMap<Int, Float>;
    public final pattern:DefaultBuilderSolid;

    public function new(?values:Null<SortedMap<Int, Float>>, ?pattern:Null<DefaultBuilderSolid>) {
        this.values = values == null ? SortedMap.builder().build() : values;
        this.pattern = pattern == null ? DefaultBuilderSolid.instance : pattern;
    }

    public static function defaultSize():Int {
        return new DefaultBuilderOps().values.size();
    }

    public static function defaultPatternIsShared():Bool {
        return new DefaultBuilderOps().pattern == DefaultBuilderSolid.instance;
    }
}
#else
class DefaultBuilderOps {}
#end
