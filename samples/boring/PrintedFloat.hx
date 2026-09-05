package boring;

import std.ReadOnlyArray;

/**
 * A printed class record with binary32 scalar fields for the f32
 * oracle text (docs/specs/features/44-record-float-text-f32.md).
 * The stops field keeps a nullable float collection outside the
 * binary32 text rule: ruling 1 covers Float and Null<Float> only.
 */
@:dataClass
class PrintedFloat {
    public final ratio:Float;
    public final offset:Null<Float>;
    public final count:Int;
    public final stops:Null<ReadOnlyArray<Float>>;

    public function new(ratio:Float, offset:Null<Float>, count:Int, stops:Null<ReadOnlyArray<Float>>) {
        this.ratio = ratio;
        this.offset = offset;
        this.count = count;
        this.stops = stops;
    }
}
