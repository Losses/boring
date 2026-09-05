package boring;

import std.ReadOnlyArray;

/** A record whose field is a ReadOnlyArray of the data-class elements. */
@:dataClass
class GlyphClusterHolder {
    public final clusters:ReadOnlyArray<GlyphCluster>;

    public function new(clusters:ReadOnlyArray<GlyphCluster>) {
        this.clusters = clusters;
    }
}