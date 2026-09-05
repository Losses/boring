package boring;

import std.ReadOnlyArray;

/**
    Reads a member of a data-class record out of a ReadOnlyArray element:
    `arr[i].clusterRange` lowers to a Kotlin array-index read followed by a
    field access, which must resolve the record member (features/49). The
    array arrives from a function whose return type is ReadOnlyArray, the
    decode-boundary shape the target renders as an asList() view.
**/
class GlyphClusterReader {
    public static function ranges():ReadOnlyArray<GlyphCluster>
        return [new GlyphCluster(3, 0, 4), new GlyphCluster(7, 4, 8)];

    public static function firstRange(holder:GlyphClusterHolder):Int {
        return holder.clusters[0].clusterRange;
    }

    public static function firstReturnedRange():Int {
        final arr:ReadOnlyArray<GlyphCluster> = ranges();
        return arr[0].clusterRange;
    }

    public static function firstWidth(holder:GlyphClusterHolder):Int {
        return holder.clusters[0].width;
    }
}
