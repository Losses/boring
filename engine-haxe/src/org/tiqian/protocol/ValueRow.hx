package org.tiqian.protocol;

class ValueRow {
    public var values:Array<Null<Float>>;

    public function new(values:Array<Null<Float>>) {
        this.values = values;
    }
}

/** One deduplicated probe style row, the 25-byte pool row unrolled. */
